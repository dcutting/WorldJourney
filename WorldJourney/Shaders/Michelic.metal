#include <metal_stdlib>
#include "Common.h"
using namespace metal;

float fbm(float, float, float, float, float);

typedef struct {
  float4 clipPosition [[position]];
  float4 worldPosition;
  float3 worldNormal;
  float3 colour;
} MichelicRasteriserData;

constant float3 ambientIntensity = 0.02;
constant float3 lightWorldPosition(200, 200, 50);
constant float3 lightColor(1.0, 1.0, 1.0);

fragment float4 michelic_fragment(MichelicRasteriserData in [[stage_in]]) {
  float3 N = normalize(in.worldNormal);
  float3 L = normalize(lightWorldPosition - in.worldPosition.xyz);
  float3 diffuseIntensity = saturate(dot(N, L));
  float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColor * in.colour;
  return float4(finalColor, 1);
}

vertex MichelicRasteriserData michelic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                              constant Uniforms &uniforms [[buffer(1)]],
                                              unsigned int vid [[vertex_id]]) {
  
  float3 templatePosition = vertex_array[vid];
  float r = uniforms.worldRadius;
  float R = r + uniforms.amplitude;
  float f = uniforms.frequency;
  float a = uniforms.amplitude;
  float3 eye = uniforms.cameraPosition;
  float4x4 mm = uniforms.modelMatrix;
  float d = length(eye);
  
  float3 v = find_terrain_for_template(templatePosition, r, R, d, f, a, eye, mm);
  
  float offsetDelta = 2.0/uniforms.gridWidth;
  float3 off = float3(offsetDelta, offsetDelta, 0.0);
  float3 vL = find_terrain_for_template(float3(templatePosition.xy - off.xz, 0.0), r, R, d, f, a, eye, mm);
  float3 vR = find_terrain_for_template(float3(templatePosition.xy + off.xz, 0.0), r, R, d, f, a, eye, mm);
  float3 vD = find_terrain_for_template(float3(templatePosition.xy - off.zy, 0.0), r, R, d, f, a, eye, mm);
  float3 vU = find_terrain_for_template(float3(templatePosition.xy + off.zy, 0.0), r, R, d, f, a, eye, mm);
  
  float3 dLR = vR - vL;
  float3 dDU = vD - vU;
  float3 worldNormal = cross(dLR, dDU);
  float4 worldPosition = float4(v, 1.0);
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
  float3 colour = float3(1.0, 1.0, 1.0);
  
  MichelicRasteriserData data;
  data.clipPosition = clipPosition;
  data.worldPosition = worldPosition;
  data.worldNormal = worldNormal;
  data.colour = colour;
  return data;
}
