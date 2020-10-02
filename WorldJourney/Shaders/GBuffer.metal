#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
#include "../Noise/ProceduralNoise.h"

using namespace metal;



/** gbuffer vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float height;
  float4 clipPosition [[position]];
  float3 modelPosition;
  float3 worldPosition;
  float3 modelGradient;
};

[[patch(quad, 4)]]
vertex EdenVertexOut gbuffer_vertex(patch_control_point<ControlPoint> control_points [[stage_in]],
                                    uint patchID [[patch_id]],
                                    float2 patch_coord [[position_in_patch]],
                                    constant Uniforms &uniforms [[buffer(1)]],
                                    constant Terrain &terrain [[buffer(2)]]) {
  
  float u = patch_coord.x;
  float v = patch_coord.y;
  float2 top = mix(control_points[0].position.xy, control_points[1].position.xy, u);
  float2 bottom = mix(control_points[3].position.xy, control_points[2].position.xy, u);
  float2 interpolated = mix(top, bottom, v);
  
  float height = control_points[0].position.z;
  float3 unitGroundLevel = float3(interpolated.x, interpolated.y, 0);
  float3 p = unitGroundLevel;
  
  TerrainSample sample = sample_terrain_michelic(p,
                                                 terrain.sphereRadius,
                                                 terrain.sphereRadius + terrain.fractal.amplitude,
                                                 length_squared(uniforms.cameraPosition),
                                                 uniforms.cameraPosition,
                                                 uniforms.modelMatrix,
                                                 terrain.fractal);
  float3 worldPosition = sample.position;
  
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPosition, 1);
  
  float3 modelPosition = unitGroundLevel;
  
  float3 modelGradient = sample.gradient;

  return {
    .height = height,
    .clipPosition = clipPosition,
    .modelPosition = modelPosition,
    .worldPosition = worldPosition,
    .modelGradient = modelGradient
  };
}



/** gbuffer fragment shader */

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

float3 sphericalise_flat_gradient(float3 g, float s, float3 x) {
  // https://math.stackexchange.com/questions/1071662/surface-normal-to-point-on-displaced-sphere
  float3 h = g - (dot(g, x) * x);
  float3 n = x - (s * h);
  return normalize(n);
}

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> normalMap [[texture(0)]]) {

  float3 normalized_position = normalize(in.worldPosition);
  
  float3 worldNormal = sphericalise_flat_gradient(in.modelGradient, terrain.fractal.amplitude, normalized_position);
  float3 worldTangent = sphericalise_flat_gradient(float3(1, 0, 0), terrain.fractal.amplitude, normalized_position);
  float3 worldBitangent = sphericalise_flat_gradient(float3(0, 1, 0), terrain.fractal.amplitude, normalized_position);
  
  float3 mappedNormal = worldNormal;

  bool useNormalMaps = true;
  if (useNormalMaps) {
    float3 normalMapValue;
    bool proceduralNormalMapping = false;
    if (proceduralNormalMapping) {
      float3 p = in.worldPosition;
      normalMapValue = simplex_noised_3d(p * 2).xyz * 2.0 - 1.0;
    } else {
      constexpr sampler normal_sample(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
      float2 p = in.worldPosition.xz + in.worldPosition.xy + in.worldPosition.yz;
      float3 distantNormalMapValue = normalMap.sample(normal_sample, p / 2000).xyz * 2.0 - 1.0;
      float3 mediumNormalMapValue = normalMap.sample(normal_sample, p / 200).xyz * 2.0 - 1.0;
      float3 closeNormalMapValue = normalMap.sample(normal_sample, p / 2).xyz * 2.0 - 1.0;
      normalMapValue = normalize(closeNormalMapValue * 0.5 + mediumNormalMapValue * 0.3 + distantNormalMapValue * 0.2);
    }
    mappedNormal = worldNormal * normalMapValue.z + worldTangent * normalMapValue.x + worldBitangent * normalMapValue.y;
  }

  return {
    .albedo = float4(0, 1, 0, 1),
    .normal = float4(normalize(mappedNormal), 1),
    .position = float4(in.worldPosition, 1)
  };
}
