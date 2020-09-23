#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
using namespace metal;

constant bool useNormalMaps = false;



/** gbuffer vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float height;
  float4 clipPosition [[position]];
  float3 modelPosition;
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
                                 texture2d<float> groundNormalMap [[texture(2)]],
                                 uint patchID [[patch_id]],
                                 float2 patch_coord [[position_in_patch]]) {
  
  float u = patch_coord.x;
  float v = patch_coord.y;
  float2 top = mix(control_points[0].position.xz, control_points[1].position.xz, u);
  float2 bottom = mix(control_points[3].position.xz, control_points[2].position.xz, u);
  float2 interpolated = mix(top, bottom, v);
  
  float3 unitGroundLevel = float3(interpolated.x, 0.0, interpolated.y);
  
  float3 modelGroundLevel = (uniforms.modelMatrix * float4(unitGroundLevel, 1)).xyz;
  
  float4 terrainSample = sample_terrain(modelGroundLevel, terrain.fractal);
  float height = terrainSample.x;
  if (height < terrain.waterLevel+1) { height = terrain.waterLevel; }
  
  float3 modelPosition = float3(modelGroundLevel.x, height, modelGroundLevel.z);
  
  float3 unit = float3(0, 1, 0);//find_unit_spherical_for_template(unitGroundLevel, terrain.sphereRadius, terrain.sphereRadius+terrain.fractal.amplitude, uniforms.cameraPosition.y);
  float3 worldPosition = unit * (terrain.sphereRadius + height);
  
  //  float3 worldPosition = modelPosition;// sphericalise(terrain.sphereRadius, modelPosition, uniforms.cameraPosition.xz);
  //  float3 worldPosition = sphericalise(terrain.sphereRadius, modelPosition, uniforms.cameraPosition.xz);
  
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPosition, 1);
  
  // TODO: need to warp normals around sphere too (?)
  NormalFrame sample = normal_frame(get_normal(terrainSample));
  float3 worldNormal = sample.normal;
  float3 worldTangent = sample.tangent;
  float3 worldBitangent = sample.bitangent;
  
  return {
    .height = height,
    .clipPosition = clipPosition,
    .modelPosition = modelPosition,
    .worldPosition = worldPosition,
    .worldNormal = worldNormal,
    .worldTangent = worldTangent,
    .worldBitangent = worldBitangent
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
                                     texture2d<float> groundNormalMap [[texture(1)]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]]) {
  GbufferOut out;
  
  if (in.height < terrain.waterLevel+1) {
    // TODO: doesn't set height correctly for curved geometry
    float3 rejigged = float3(in.modelPosition.x, terrain.waterLevel, in.modelPosition.z);
    out.position = float4(rejigged, 1);//float4(sphericalise(terrain.sphereRadius, rejigged, uniforms.cameraPosition.xz), (float)in.height / (float)terrain.fractal.amplitude);
    out.albedo = float4(.098, .573, .80, 1);
  } else {
    out.position = float4(in.worldPosition, (float)in.height / (float)terrain.fractal.amplitude);
    out.albedo = float4(1, 1, 1, 0.4);
  }
  
  float3 n = in.worldNormal;
  
  if (useNormalMaps) {
    
    constexpr sampler normal_sample(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    
    float2 xz = in.worldPosition.xz;
    
    float3 distantNormalMapValue = groundNormalMap.sample(normal_sample, xz / 2000).xyz * 2.0 - 1.0;
    
    float3 mediumNormalMapValue = groundNormalMap.sample(normal_sample, xz / 200).xyz * 2.0 - 1.0;
    
    float3 closeNormalMapValue = groundNormalMap.sample(normal_sample, xz / 2).xyz * 2.0 - 1.0;
    
    float3 normalMapValue = normalize(closeNormalMapValue * 0.5 + mediumNormalMapValue * 0.3 + distantNormalMapValue * 0.2);
    
    n = n * normalMapValue.z + in.worldTangent * normalMapValue.x + in.worldBitangent * normalMapValue.y;
  }
  
  out.normal = float4(normalize(n), 1);
  
  return out;
}
