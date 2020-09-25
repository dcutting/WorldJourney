#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"

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
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
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
  float3 unitGroundLevel = float3(interpolated.x * 2, interpolated.y, 0.9);
  
  float4 clipPosition = float4(unitGroundLevel, 1);// uniforms.projectionMatrix * uniforms.viewMatrix * float4(unitGroundLevel, 1);
  
  float3 modelPosition = unitGroundLevel;
  float3 worldPosition = unitGroundLevel;
  float3 worldNormal = float3(0, 1, 0);
  float3 worldTangent = float3(1, 0, 0);
  float3 worldBitangent = float3(0, 0, 1);

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
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]]) {
  return {
    .albedo = float4(0, 1, 0, 1),
    .normal = float4(normalize(in.worldNormal), 1),
    .position = float4(in.worldPosition, 1)
  };
}
