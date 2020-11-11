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

vertex ObjectOut object_vertex(ObjectIn vertexIn [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               ushort iid [[instance_id]]) {
  ObjectOut vertexOut;
  vertexOut.position = uniforms.projectionMatrix * float4(vertexIn.position + float3(-5 + iid * 10.5, -3 + iid, -30 * iid), 1);
  vertexOut.normal = vertexIn.normal;
  vertexOut.texCoords = vertexIn.texCoords;
  return vertexOut;
}

fragment float4 object_fragment(ObjectOut in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(0)]]) {
  float diffuse = saturate(dot(in.normal, -normalize(uniforms.sunDirection)));
  float3 colour(1, 1, 1);
  float3 lit = (uniforms.ambient + diffuse) * uniforms.sunColour * colour;
  if (uniforms.renderMode == 1) {
    return float4(in.normal, 1);
  }
  return float4(lit, 1);
}
