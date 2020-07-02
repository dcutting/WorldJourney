#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "ValueNoise.h"
using namespace metal;

constant bool shadows = true;

constant float3 ambientIntensity = 0.3;
constant float3 lightColour(1.0);

constexpr sampler repeat_sample(coord::normalized, address::repeat, filter::linear);

float random(float2 st, texture2d<float> noiseMap) {
    return noiseMap.sample(repeat_sample, st).r;
}

float fbm(float2 st, Fractal fractal, int octaves, texture2d<float> noiseMap) {
    float value = 0.0;
    float f = fractal.frequency;
    float a = fractal.amplitude;
    for (int i = 0; i < octaves; i++) {
        value += a * random(st * f, noiseMap);
        f *= fractal.lacunarity;
        a *= fractal.persistence;
   }
   return value;
}

float terrain_height_coarse(float2 xz, float height, texture2d<float> heightMap) {
    float4 color = heightMap.sample(repeat_sample, xz);
    return color.r * height;
}

float terrain_height_noise(float2 xz, Terrain terrain, int octaves, texture2d<float> heightMap, texture2d<float> noiseMap) {
        float coarse = terrain_height_coarse(xz, terrain.height, heightMap);
//    float noise = fbm(xz, terrain.fractal, octaves, noiseMap);
//    return noise;// coarse + noise;
//    float noise = 0;//random(xz*16, noiseMap)*0.1 + random(xz*32, noiseMap)*0.05 + random(xz*64, noiseMap)*0.025;

    float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
    xz *= m;
    float noise = terrain_height_coarse(xz, terrain.height / 128, noiseMap);
    xz *= m;
    noise += terrain_height_coarse(xz * 2, terrain.height / 256, noiseMap);
//    xz *= m;
//    noise += terrain_height_coarse(xz * 7.6, terrain.height / 256, noiseMap);

    return coarse + noise;
}

float terrain_height_noise(float2 xz, Terrain terrain, texture2d<float> heightMap, texture2d<float> noiseMap) {
    return terrain_height_noise(xz, terrain, terrain.fractal.octaves, heightMap, noiseMap);
}

float calc_distance(float3 pointA, float3 pointB, float3 camera_position) {
    float3 midpoint = (pointA + pointB) * 0.5;
    return distance(camera_position, midpoint);
}

float2 normalise_point(float2 xz, Terrain terrain) {
    return (xz + terrain.size / 2.0) / terrain.size;
}

kernel void eden_tessellation(constant float *edge_factors [[buffer(0)]],
                              constant float *inside_factors [[buffer(1)]],
                              device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                              constant float3 *control_points [[buffer(3)]],
                              constant Uniforms &uniforms [[buffer(4)]],
                              constant Terrain &terrain [[buffer(5)]],
                              texture2d<float> heightMap [[texture(0)]],
                              texture2d<float> noiseMap [[texture(1)]],
                              uint pid [[thread_position_in_grid]]) {
    
    uint index = pid * 4;
    float totalTessellation = 0;
    for (int i = 0; i < 4; i++) {
        int pointAIndex = i;
        int pointBIndex = i + 1;
        if (pointAIndex == 3) {
            pointBIndex = 0;
        }
        int edgeIndex = pointBIndex;
        
        float2 pA1 = (uniforms.modelMatrix * float4(control_points[pointAIndex + index], 1)).xz;
        float2 pA = normalise_point(pA1, terrain);
        float aH = terrain_height_noise(pA, terrain, heightMap, noiseMap);
        float3 pointA = float3(pA1.x, aH, pA1.y);
        
        float2 pB1 = (uniforms.modelMatrix * float4(control_points[pointBIndex + index], 1)).xz;
        float2 pB = normalise_point(pB1, terrain);
        float bH = terrain_height_noise(pB, terrain, heightMap, noiseMap);
        float3 pointB = float3(pB1.x, bH, pB1.y);
        
        float3 camera = uniforms.cameraPosition;
        
        float cameraDistance = calc_distance(pointA,
                                             pointB,
                                             camera);
        float tessellation = max(1.0, terrain.tessellation / (cameraDistance / (TERRAIN_SIZE / PATCH_SIDE * 4)));
        factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
        totalTessellation += tessellation;
    }
    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}

struct ControlPoint {
    float4 position [[attribute(0)]];
};

kernel void eden_height(texture2d<float> heightMap [[texture(0)]],
                        texture2d<float> noiseMap [[texture(1)]],
                        constant Terrain &terrain [[buffer(0)]],
                        constant float2 &xz [[buffer(1)]],
                        volatile device float *height [[buffer(2)]],
                        uint gid [[ thread_position_in_grid ]]) {
    float2 axz = normalise_point(xz, terrain);
    *height = terrain_height_noise(axz, terrain, heightMap, noiseMap);
}

typedef struct {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
} EdenVertexOut;

[[patch(quad, 4)]]
vertex EdenVertexOut eden_vertex(patch_control_point<ControlPoint>
                                 control_points [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]],
                                 constant Terrain &terrain [[buffer(2)]],
                                 texture2d<float> heightMap [[texture(0)]],
                                 texture2d<float> noiseMap [[texture(1)]],
                                 uint patchID [[patch_id]],
                                 float2 patch_coord [[position_in_patch]]) {
    float u = patch_coord.x;
    float v = patch_coord.y;
    
    float2 top = mix(control_points[0].position.xz,
                     control_points[1].position.xz, u);
    float2 bottom = mix(control_points[3].position.xz,
                        control_points[2].position.xz, u);
    
    float2 interpolated = mix(top, bottom, v);
    
    float4 position = float4(interpolated.x, 0.0, interpolated.y, 1.0);
    float2 xz = (position.xz + terrain.size / 2.0) / terrain.size;
    float noise = terrain_height_noise(xz, terrain, heightMap, noiseMap);
    position.y = noise;
    
    float eps = 0.5;
    
    float3 t_pos = position.xyz;
    
    float2 br = t_pos.xz + float2(eps, 0);
    float2 brz = (br + terrain.size / 2.0) / terrain.size;
    float hR = terrain_height_noise(brz, terrain, heightMap, noiseMap);
    
    float2 tl = t_pos.xz + float2(0, eps);
    float2 tlz = (tl + terrain.size / 2.0) / terrain.size;
    float hU = terrain_height_noise(tlz, terrain, heightMap, noiseMap);
    
    float3 normal = float3(position.y - hR, eps, position.y - hU);
    
    float4 clipPosition = uniforms.mvpMatrix * position;
    float3 worldPosition = position.xyz;
    float3 worldNormal = normal;
    
    return {
        .clipPosition = clipPosition,
        .worldPosition = worldPosition,
        .worldNormal = worldNormal
    };
}

float4 lighting(float3 position,
                float3 N,
                constant Uniforms &uniforms [[buffer(0)]],
                constant Terrain &terrain [[buffer(1)]],
                texture2d<float> rockTexture [[texture(3)]],
                texture2d<float> heightMap [[texture(5)]],
                texture2d<float> noiseMap [[texture(6)]]) {
//    float3 rockClose = rockTexture.sample(repeat_sample, position.xz / 5).xyz;
    //N += rockClose;
    //        N += float3(rockNoiseA, rockNoiseB, rockNoiseC);
    //    N = normalize(N);
    float3 L = normalize(uniforms.lightPosition - position);
    float flatness = dot(N, float3(0, 1, 0));
    //    float ds = distance_squared(uniforms.cameraPosition, in.worldPosition) / ((terrain.size * terrain.size));
    //        float3 rockFar = rockTexture.sample(repeat_sample, in.worldPosition.xz / 50).xyz;
        float3 rock = float3(0.7, 0.4, 0.3);//rockClose;//mix(rockClose, rockFar, saturate(ds * 5000));
//    float3 rock = rockClose;
    //    float3 snowFar = snowTexture.sample(repeat_sample, in.worldPosition.xz / 30).xyz;
    //        float3 snowClose = snowTexture.sample(repeat_sample, position.xz / 5).xyz;
    float3 snow = float3(1);//mix(snowClose, snowFar, saturate(ds * 500));

    float3 grass = float3(0.4, 0.7, 0.3);
    float stepped = smoothstep(0.95, 1.0, flatness);
    float3 water = float3(0.1, 0.3, 0.8);
    float3 plain = position.y < 0.5 ? water : position.y > 20 ? snow : grass;
    float3 c = mix(rock, plain, stepped);
//        float3 c = float3(1);// mix(rock, snow, stepped);
    //    float3 c = albedo.xyz;
    
    float3 diffuseIntensity;
    //    if (uniforms.lightPosition.y > 0) {
    diffuseIntensity = saturate(dot(N, L));
    //    } else {
    //        diffuseIntensity = float3(0.0);
    //    }
    
    // raymarch toward light
    //    constexpr sampler heightSampler;
    
    float3 shadowed = 0.0;
    
    if (shadows) {
        // TODO Some bug here when sun goes under the world.
        float3 origin = position;
        
        //        float light_height = uniforms.lightPosition.y;// - origin.y;
        //        float terrain_height = terrain.height;// - origin.y;
        //        float ratio = terrain_height / light_height;
        //        float3 light_to_origin = uniforms.lightPosition - origin;
        //        float light_distance_sq = length_squared(light_to_origin);
        //        float max_dist_sq = ratio * light_distance_sq;
        
        float max_dist = TERRAIN_SIZE;
        
        //        float3 direction = normalize(light_to_origin);
        
        float min_step_size = 1;
        float step_size = min_step_size;
        for (float d = step_size; d < max_dist; d += step_size) {
            float3 tp = origin + L * d;
            if (tp.y > terrain.height) {
                break;
            }
            
            float2 xy = (tp.xz + terrain.size / 2.0) / terrain.size;
            float height = terrain_height_noise(xy, terrain, 2, heightMap, noiseMap);
            if (height > tp.y) {
//                return float4(1, 0, 1, 1);
                shadowed = diffuseIntensity;
                break;
            }
            min_step_size *= 2;
            step_size = max(min_step_size, (tp.y - height)/2);
        }
    }
    
    
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity - shadowed) * lightColour * c;
    return float4(finalColor, 1);
    
    
    //  float4 albedo = albedoTexture.sample(s, in.texCoords);
    //  float3 normal = normalTexture.sample(s, in.texCoords).xyz;
    //  float3 position = positionTexture.sample(s, in.texCoords).xyz;
    //  float3 baseColor = albedo.rgb;
    //    float3 diffuseColor = albedo.xyz;//.xyz;//float3(1,0,0.5);// compositeLighting(normal, position,
    ////                                          fragmentUniforms, lightsBuffer, baseColor);
    ////  float shadow = albedo.a;
    ////  if (shadow > 0) {
    ////    diffuseColor *= 0.5;
    ////  }
    //  return float4(diffuseColor, 1);
}

fragment float4 eden_fragment(EdenVertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(0)]],
                              constant Terrain &terrain [[buffer(1)]],
                              texture2d<float> rockTexture [[texture(0)]],
                              texture2d<float> snowTexture [[texture(1)]],
                              texture2d<float> heightMap [[texture(2)]],
                              texture2d<float> noiseMap [[texture(3)]]
                              ) {
    float3 N = normalize(in.worldNormal);
    return lighting(in.worldPosition, N, uniforms, terrain, rockTexture, heightMap, noiseMap);
}

struct GbufferOut {
    float4 albedo [[color(0)]];
    float4 normal [[color(1)]];
    float4 position [[color(2)]];
};

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]]
                                     //depth2d<float> shadow_texture [[texture(0)]],
                                     //constant Material &material [[buffer(1)]])
                                     ) {
    GbufferOut out;
    
    out.albedo = float4(1);//,0,1,1);//float4(material.baseColor, 1.0);
    //  out.albedo.a = 0;
    out.normal = float4(normalize(in.worldNormal), 1.0);
    out.position = float4(in.worldPosition, 1.0);
    
    // copy from fragment_main
    //  float2 xy = in.shadowPosition.xy;
    //  xy = xy * 0.5 + 0.5;
    //  xy.y = 1 - xy.y;
    //  constexpr sampler s(coord::normalized, filter::linear,
    //                      address::clamp_to_edge, compare_func:: less);
    //  float shadow_sample = shadow_texture.sample(s, xy);
    //  float current_sample = in.shadowPosition.z / in.shadowPosition.w;
    //
    //  if (current_sample > shadow_sample ) {
    //    out.albedo.a = 1;
    //  }
    return out;
}

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

vertex VertexOut composition_vertex(constant float2 *quadVertices [[buffer(0)]],
                                    constant float2 *quadTexCoords [[buffer(1)]],
                                    uint id [[vertex_id]]
                                    ) {
    VertexOut out;
    out.position = float4(quadVertices[id], 0.0, 1.0);
    out.texCoords = quadTexCoords[id];
    return out;
}

fragment float4 composition_fragment(VertexOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> albedoTexture [[texture(0)]],
                                     texture2d<float> normalTexture [[texture(1)]],
                                     texture2d<float> positionTexture [[texture(2)]],
                                     texture2d<float> rockTexture [[texture(3)]],
                                     texture2d<float> heightMap [[texture(5)]],
                                     texture2d<float> noiseMap [[texture(6)]]
                                     //depth2d<float> shadowTexture [[texture(4)]])
                                     ) {
    
    constexpr sampler s(min_filter::linear, mag_filter::linear);
    
    float4 albedo = albedoTexture.sample(s, in.texCoords);
    
    if (albedo.r < 0.5) {
        return float4(0.2, 0.3, 0.7, 1.0);
    }
    
    float3 position = positionTexture.sample(s, in.texCoords).xyz;
    float3 N = normalTexture.sample(s, in.texCoords).xyz;
    
    return lighting(position, N, uniforms, terrain, rockTexture, heightMap, noiseMap);
}
