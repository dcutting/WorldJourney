#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
#include "Noise.h"

using namespace metal;



/** gbuffer vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float height;
  int octaves;
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
  
  Fractal fractal = terrain.fractal;

  float r = terrain.sphereRadius;
  float R = terrain.sphereRadius + (fractal.amplitude / 2.0);

  float height = control_points[0].position.z;
  float3 unitGroundLevel = float3(interpolated.x, interpolated.y, 0);
  float3 p = unitGroundLevel;

  float d_sq = length_squared(uniforms.cameraPosition);
  float3 eye = uniforms.cameraPosition;
  
  float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d_sq, eye);
  float3 modelled = unit_spherical * R;

  bool adjust_octaves = false;
  if (adjust_octaves) {
    float tbd = distance(eye, modelled);
    float tbds = pow(100000.0 / tbd, 0.4);
    float max_octaves = 8;
    float no = (float)max_octaves * (tbds);
    int new_octaves = clamp(no, 1.0, max_octaves);
    fractal.octaves = (int)new_octaves;
  }
    
  TerrainSample sample = sample_terrain_michelic(p,
                                                 r,
                                                 R,
                                                 d_sq,
                                                 eye,
                                                 fractal);
  float3 worldPosition = sample.position;
  
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPosition, 1);
  
  float3 modelPosition = unitGroundLevel;
  
  float3 modelGradient = sample.gradient;

  return {
    .height = height,
    .octaves = fractal.octaves,
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

constexpr sampler s(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

float4 boxmap(float3 p, float3 n, float k, texture2d<float> texture) {
  
  // project+fetch
  float4 x = texture.sample(s, p.yz);
  float4 y = texture.sample(s, p.zx);
  float4 z = texture.sample(s, p.xy);
  
  // blend factors
  float3 w = pow(abs(n), float3(k));
  // blend and return
  return (x*w.x + y*w.y + z*w.z) / (w.x + w.y + w.z);
}

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> normalMap [[texture(0)]],
                                     texture2d<float> normalMap2 [[texture(1)]]) {

  float3 unitSurfacePoint = normalize(in.worldPosition);
  
  float3 worldNormal = sphericalise_flat_gradient(in.modelGradient, terrain.fractal.amplitude, unitSurfacePoint);
  float3 worldTangent = sphericalise_flat_gradient(float3(1, 0, 0), terrain.fractal.amplitude, unitSurfacePoint);
  float3 worldBitangent = sphericalise_flat_gradient(float3(0, 1, 0), terrain.fractal.amplitude, unitSurfacePoint);
  
#ifdef USE_NORMAL_MAPS
  float3 mediumNormalMapValue = boxmap(in.worldPosition / 400, worldNormal, 3, normalMap2).xyz;
  float3 closeNormalMapValue = boxmap(in.worldPosition / 10, worldNormal, 8, normalMap).xyz;
  float3 normalMapValue = (closeNormalMapValue * 0.5 + mediumNormalMapValue * 0.5) - 0.5;
  float3 mappedNormal = worldNormal * normalMapValue.z + worldTangent * normalMapValue.x + worldBitangent * normalMapValue.y;
#else
  float3 mappedNormal = worldNormal;
#endif
  
  float4 albedo = float4(0, 1, 0, 1);

  return {
    .albedo = albedo,
    .normal = float4(normalize(mappedNormal), 1),
    .position = float4(in.worldPosition, 1)
  };
}