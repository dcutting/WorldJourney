#include <metal_stdlib>
#include "Common.h"
using namespace metal;

constant float3 ambientIntensity = 0.3;
constant float3 lightWorldPosition(TERRAIN_SIZE*2, TERRAIN_SIZE*2, TERRAIN_SIZE*2);
constant float3 lightColour(1.0);

constexpr sampler mirrored_sample(coord::normalized, address::mirrored_repeat, filter::linear);
constexpr sampler repeat_sample(coord::normalized, address::repeat, filter::linear);

float random(float2 st, texture2d<float> noiseMap) {
    return noiseMap.sample(mirrored_sample, st).r;
}

float fbm(float2 st, Fractal fractal, texture2d<float> noiseMap) {
    float value = 0.0;
    float f = fractal.frequency;
    float a = fractal.amplitude;
    for (int i = 0; i < fractal.octaves; i++) {
        value += a * random(st * f, noiseMap);
        f *= fractal.lacunarity;
        a *= fractal.persistence;
   }
   return value;
}

float terrain_height_coarse(float2 xz, Terrain terrain, texture2d<float> heightMap) {
    float4 color = heightMap.sample(mirrored_sample, xz);
    return color.r * terrain.height;
}

float terrain_height_noise(float2 xz, Terrain terrain, texture2d<float> heightMap, texture2d<float> noiseMap) {
    float coarse = terrain_height_coarse(xz, terrain, heightMap);
    float noise = fbm(xz, terrain.fractal, noiseMap);
    return coarse + noise;
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
        float tessellation = max(1.0, terrain.tessellation / (cameraDistance / (TERRAIN_SIZE / PATCH_SIDE)));
        factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
        totalTessellation += tessellation;
    }
    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}

typedef struct {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
} EdenVertexOut;

struct ControlPoint {
    float4 position [[attribute(0)]];
};

kernel void eden_height(texture2d<float> heightMap [[texture(0)]],
                        texture2d<float> noiseMap [[texture(1)]],
                        constant Terrain &terrain [[buffer(0)]],
                        constant float2 &xz [[buffer(1)]],
                        volatile device float *height [[buffer(2)]],
                        uint gid [[ thread_position_in_grid ]]) {
    float2 axz = (xz + terrain.size / 2.0) / terrain.size;
    float2 eps = float2(0, 0.002);
    float k = terrain_height_noise(axz, terrain, heightMap, noiseMap);
    float a = terrain_height_noise(axz + eps.xy, terrain, heightMap, noiseMap);
    float b = terrain_height_noise(axz + eps.yx, terrain, heightMap, noiseMap);
    float c = terrain_height_noise(axz - eps.xy, terrain, heightMap, noiseMap);
    float d = terrain_height_noise(axz - eps.yx, terrain, heightMap, noiseMap);
    *height = (k + a + b + c + d) / 5.0;
}

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
    position.y = terrain_height_noise(xz, terrain, heightMap, noiseMap);
    
    float eps = 1;//100000 / distance_squared(uniforms.cameraPosition.xyz, position.xyz);
    
    float3 t_pos = position.xyz;
    
    float2 br = t_pos.xz + float2(eps, 0);
    float2 brz = (br + terrain.size / 2.0) / terrain.size;
    float hR = terrain_height_noise(brz, terrain, heightMap, noiseMap);
    
    float2 br2 = t_pos.xz + float2(-eps, 0);
    float2 brz2 = (br2 + terrain.size / 2.0) / terrain.size;
    float hL = terrain_height_noise(brz2, terrain, heightMap, noiseMap);
    
    float2 tl = t_pos.xz + float2(0, eps);
    float2 tlz = (tl + terrain.size / 2.0) / terrain.size;
    float hU = terrain_height_noise(tlz, terrain, heightMap, noiseMap);
    
    float2 tl2 = t_pos.xz + float2(0, -eps);
    float2 tlz2 = (tl2 + terrain.size / 2.0) / terrain.size;
    float hD = terrain_height_noise(tlz2, terrain, heightMap, noiseMap);
    
    float3 normal = float3(hL - hR, eps * 2, hD - hU);
    
    float4 clipPosition = uniforms.mvpMatrix * position;
    float3 worldPosition = position.xyz;
    float3 worldNormal = normal;
    
    return {
        .clipPosition = clipPosition,
        .worldPosition = worldPosition,
        .worldNormal = worldNormal
    };
}

fragment float4 eden_fragment(EdenVertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(0)]],
                              constant Terrain &terrain [[buffer(1)]],
                              texture2d<float> rockTexture [[texture(0)]],
                              texture2d<float> snowTexture [[texture(1)]]) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition);
    float flatness = dot(N, float3(0, 1, 0));
    float ds = distance_squared(uniforms.cameraPosition, in.worldPosition) / ((terrain.size * terrain.size));
    float3 rockFar = rockTexture.sample(repeat_sample, in.worldPosition.xz / 50).xyz;
    float3 rockClose = rockTexture.sample(repeat_sample, in.worldPosition.xz / 5).xyz;
    float3 rock = mix(rockClose, rockFar, saturate(ds * 5000));
    float3 snowFar = snowTexture.sample(repeat_sample, in.worldPosition.xz / 30).xyz;
    float3 snowClose = snowTexture.sample(repeat_sample, in.worldPosition.xz / 5).xyz;
    float3 snow = mix(snowClose, snowFar, saturate(ds * 500));
    float stepped = smoothstep(0.85, 1.0, flatness);
    float3 c = mix(rock, snow, stepped);
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColour * c;
    return float4(finalColor, 1);
}
