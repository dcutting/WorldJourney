#include <metal_stdlib>
#import "../Common.h"

using namespace metal;

struct VertexIn {
  float4 position [[ attribute(0) ]];
};

struct VertexOut {
  float4 position [[ position ]];
  float2 screenUV;
  float3 uv;
};

vertex VertexOut vertexSkybox(const VertexIn in [[stage_in]],
                              constant float4x4 &vp [[buffer(1)]],
                              constant Uniforms &uniforms [[buffer(2)]]) {
  VertexOut out;
  float4 t = uniforms.projectionMatrix * uniforms.viewMatrix * in.position;
  out.position = (vp * in.position).xyww;
  out.screenUV = (t.xy / 1) / 2.0 + 0.5;
  out.uv = in.position.xyz;
  return out;
}

fragment float4 fragmentSkybox(VertexOut in [[stage_in]],
                              texturecube<float> cubeTexture [[texture(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
  constexpr sampler default_sampler(filter::linear);
  return cubeTexture.sample(default_sampler, in.uv);
}
