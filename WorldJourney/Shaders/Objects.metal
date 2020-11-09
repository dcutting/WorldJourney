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
    float4 normal;
    float2 texCoords;
};

vertex ObjectOut object_vertex(ObjectIn vertexIn [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]]) {
  ObjectOut vertexOut;
  vertexOut.position = uniforms.projectionMatrix * float4(vertexIn.position + float3(-3.8, -4.5, -15), 1);
  vertexOut.normal = float4(vertexIn.normal, 0);
  vertexOut.texCoords = vertexIn.texCoords;
  return vertexOut;
}

fragment float4 object_fragment(ObjectOut in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(0)]]) {
  float diffuse = saturate(dot(in.normal.xyz, -normalize(uniforms.sunDirection)));
  float3 colour(1, 1, 1);
  float3 lit = (uniforms.ambient + diffuse) * uniforms.sunColour * colour;
  return float4(lit, 1);
}
