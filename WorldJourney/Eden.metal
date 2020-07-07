#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "ValueNoise.h"

using namespace metal;

constant bool shadows = true;
constant float3 ambientIntensity = 0.2;
constant float3 lightColour(1.0);
constant float waterLevel = 17;



float terrain_height_map(float2 xz, float height, texture2d<float> heightMap) {
  constexpr sampler height_sample(coord::normalized, address::clamp_to_zero, filter::linear);
  float4 color = heightMap.sample(height_sample, xz, level(0));
  return color.r * height;
}

float2 normalise_point(float2 xz, Terrain terrain) {
  return (xz + terrain.size / 2.0) / terrain.size;
}



/** height kernel */

kernel void eden_height(texture2d<float> heightMap [[texture(0)]],
                        texture2d<float> noiseMap [[texture(1)]],
                        constant Terrain &terrain [[buffer(0)]],
                        constant float2 &xz [[buffer(1)]],
                        volatile device float *height [[buffer(2)]],
                        uint gid [[thread_position_in_grid]]) {
  
  float2 axz = normalise_point(xz, terrain);
  *height = terrain_height_map(axz, terrain.height, heightMap);
}



/** tessellation kernel */

float calc_distance(float3 pointA, float3 pointB, float3 camera_position) {
  float3 midpoint = (pointA + pointB) * 0.5;
  return distance(camera_position, midpoint);
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
    float aH = terrain_height_map(pA, terrain.height, heightMap);
    float3 pointA = float3(pA1.x, aH, pA1.y);
    
    float2 pB1 = (uniforms.modelMatrix * float4(control_points[pointBIndex + index], 1)).xz;
    float2 pB = normalise_point(pB1, terrain);
    float bH = terrain_height_map(pB, terrain.height, heightMap);
    float3 pointB = float3(pB1.x, bH, pB1.y);
    
    float3 camera = uniforms.cameraPosition;
    
    float cameraDistance = calc_distance(pointA,
                                         pointB,
                                         camera);
    float stepped = 1 - smoothstep(PATCH_GRANULARITY, 600, cameraDistance);
    int minTessellation = 3;
    float tessellation = minTessellation + stepped * (terrain.tessellation - minTessellation);
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}



/** vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float4 clipPosition [[position]];
  float3 worldPosition;
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
};

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
  float2 xz = normalise_point(position.xz, terrain);
  float noise = terrain_height_map(xz, terrain.height, heightMap);
  
  float3 normal;
  float3 tangent;
  float3 bitangent;
  
  if (noise <= waterLevel) {
    noise = waterLevel;
    normal = float3(0, 1, 0);
    tangent = float3(1, 0, 0);
    bitangent = float3(0, 0, 1);
  } else {
    position.y = noise;
    
    float eps = 3;
    
    float3 t_pos = position.xyz;
    
    float2 br = t_pos.xz + float2(eps, 0);
    float2 brz = normalise_point(br, terrain);
    float hR = terrain_height_map(brz, terrain.height, heightMap);
    
    float2 tl = t_pos.xz + float2(0, eps);
    float2 tlz = normalise_point(tl, terrain);
    float hU = terrain_height_map(tlz, terrain.height, heightMap);
    
    tangent = normalize(float3(br.x, position.y - hR, 0));
    
    bitangent = normalize(float3(0, position.y - hU, tl.y));
    
    normal = normalize(float3(position.y - hR, eps, position.y - hU));
    
  }
  
  float4 clipPosition = uniforms.mvpMatrix * position;
  float3 worldPosition = position.xyz;
  float3 worldNormal = normal;
  
  return {
    .clipPosition = clipPosition,
    .worldPosition = worldPosition,
    .worldNormal = worldNormal,
    .worldTangent = tangent,
    .worldBitangent = bitangent
  };
}



/** gbuffer fragment shader */

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]],
                                     texture2d<float> cliffNormalMap [[texture(0)]],
                                     texture2d<float> snowNormalMap [[texture(1)]],
                                     constant Uniforms &uniforms [[buffer(0)]]) {
  GbufferOut out;
  
  if (in.worldPosition.y < waterLevel+1) {
    out.position = float4(in.worldPosition.x, waterLevel, in.worldPosition.z, 1);
    out.albedo = float4(.098, .573, .80, 1);
  } else {
    out.position = float4(in.worldPosition, 1.0);
    out.albedo = float4(1, 1, 1, 0.4);
  }
  
  float3 n = in.worldNormal;
  
  float flatness = dot(n, float3(0, 1, 0));
  
  float stepped = smoothstep(0.75, 1.0, flatness);
  
  constexpr sampler normal_sample(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
  
  float3 cliffNormalMapValue = cliffNormalMap.sample(normal_sample, in.worldPosition.xz / 5).xyz * 2.0 - 1.0;
  float3 snowNormalMapValue = snowNormalMap.sample(normal_sample, in.worldPosition.xz / 5).xyz * 2.0 - 1.0;
  
  float3 normalMapValue = mix(cliffNormalMapValue, snowNormalMapValue, stepped);
  
  n = n * normalMapValue.z + in.worldTangent * normalMapValue.x + in.worldBitangent * normalMapValue.y;
  
  out.normal = float4(normalize(n), 1);
  
  return out;
}



/** composition vertex shader */

struct CompositionVertexOut {
  float4 position [[position]];
  float2 uv;
};

vertex CompositionVertexOut composition_vertex(constant float2 *vertices [[buffer(0)]],
                                               constant float2 *uv [[buffer(1)]],
                                               uint id [[vertex_id]]) {
  return {
    .position = float4(vertices[id], 0.0, 1.0),
    .uv = uv[id]
  };
}



/** composition fragment shader */

float4 lighting(float3 position,
                float3 N,
                float4 albedo,
                constant Uniforms &uniforms [[buffer(0)]],
                constant Terrain &terrain [[buffer(1)]],
                texture2d<float> rockTexture [[texture(3)]],
                texture2d<float> heightMap [[texture(5)]],
                texture2d<float> noiseMap [[texture(6)]],
                texture2d<float> normalMap [[texture(7)]]) {

  float3 L = normalize(uniforms.lightPosition - position);
  
  if (albedo.a < 0.5) {
    float flatness = dot(N, float3(0, 1, 0));
    //        float ds = distance_squared(uniforms.cameraPosition, position) / ((terrain.size * terrain.size));
    //        float3 rockFar = float3(0x75/255.0, 0x5D/255.0, 0x43/255.0);//rockTexture.sample(repeat_sample, position.xz / 100).xyz;
    //        float3 rockClose = rockTexture.sample(repeat_sample, position.xz / 10).xyz;
    //        float3 rock = mix(rockClose, rockFar, saturate(ds * 1000));
    float3 rock = float3(0.6, 0.3, 0.2);
    float3 snow = float3(1);
    
    float3 grass = float3(.663, .80, .498);
    float stepped = smoothstep(0.65, 1.0, flatness);
    float3 plain = position.y > 200 ? snow : grass;
    float3 c = mix(rock, plain, stepped);
    albedo = float4(c, 1);
  }
  
  float diffuseIntensity = saturate(dot(N, L));

  float3 specularColor = 0;
  float materialShininess = 256;
  float3 materialSpecularColor = float3(1, 1, 1);
  
  if (diffuseIntensity > 0 && position.y < waterLevel+1) {
    float3 reflection = reflect(L, N);
    float3 cameraDirection = normalize(position - uniforms.cameraPosition);
    float specularIntensity = pow(saturate(dot(reflection, cameraDirection)), materialShininess);
    specularColor = lightColour * materialSpecularColor * specularIntensity;
  }
  
  float3 shadowed = 0.0;
  
  if (shadows) {
    // TODO Some bug here when sun goes under the world.
    float3 origin = position;
    
    float max_dist = TERRAIN_SIZE;
    
    float min_step_size = 1;
    float step_size = min_step_size;
    for (float d = step_size*5; d < max_dist; d += step_size) {
      float3 tp = origin + L * d;
      if (tp.y > terrain.height) {
        break;
      }
      
      float2 xz = normalise_point(tp.xz, terrain);
      float height = terrain_height_map(xz, terrain.height, heightMap);
      if (height > tp.y) {
        shadowed = diffuseIntensity;
        break;
      }
      min_step_size *= 2;
      step_size = max(min_step_size, (tp.y - height)/2);
    }
  }
  
  float3 finalColor = saturate(ambientIntensity + diffuseIntensity - shadowed + specularColor) * lightColour * albedo.xyz;
  return float4(finalColor, 1);
}



fragment float4 composition_fragment(CompositionVertexOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> albedoTexture [[texture(0)]],
                                     texture2d<float> normalTexture [[texture(1)]],
                                     texture2d<float> positionTexture [[texture(2)]],
                                     texture2d<float> rockTexture [[texture(3)]],
                                     texture2d<float> heightMap [[texture(5)]],
                                     texture2d<float> noiseMap [[texture(6)]],
                                     texture2d<float> normalMap [[texture(7)]]) {
  
  constexpr sampler sample(min_filter::linear, mag_filter::linear);
  
  float4 albedo = albedoTexture.sample(sample, in.uv);
  
  if (albedo.a < 0.1) {
    float4 sky = float4(.529, .808, .922, 1);
    return sky;
  }
  
  float3 position = positionTexture.sample(sample, in.uv).xyz;
  float3 normal = normalTexture.sample(sample, in.uv).xyz;
  
  return lighting(position, normal, albedo, uniforms, terrain, rockTexture, heightMap, noiseMap, normalMap);
}
