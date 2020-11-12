#include <metal_stdlib>
#include "../Common.h"

using namespace metal;

struct ObjectIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};

struct ObjectOut {
    float4 position [[position]];
    float3 normal;
    float2 texCoords;
};

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

vertex ObjectOut object_vertex(ObjectIn vertexIn [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               ushort iid [[instance_id]]) {
  ObjectOut vertexOut;
  vertexOut.position = uniforms.projectionMatrix * float4(vertexIn.position + float3(-5 + iid * 10.5, iid, -20 + -30 * iid), 1);
  vertexOut.normal = vertexIn.normal;
  vertexOut.texCoords = vertexIn.texCoords;
  return vertexOut;
}

fragment GbufferOut object_fragment(ObjectOut in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(0)]]) {
  return {
    .albedo = float4(1, 0, 0, 1),
    .normal = float4(normalize(in.normal), 1),
    .position = in.position
  };
}
