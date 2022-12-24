//
//  Shaders.metal
//  Terrainium
//
//  Created by Dan Cutting on 21/12/2022.
//  Copyright © 2022 cutting.io. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

#include "Common.h"
#include "../WorldJourney/Noise.h"

constant float PI = 3.14159;

struct VertexOut {
  float4 position [[position]];
  float3 normal;
};

vertex VertexOut terrainium_vertex(constant float3 *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   uint id [[vertex_id]]) {
  float4 v = float4(vertices[id], 1.0);
//  float4 noise = fbm(v.xyz, 1);
//  float4 noise = fbmd_7(v.xyz, 2, 0.2, 2, 0.5, 8);
  float3 noise = fbm2(v.xz, 6);
  float2 n(0);
  if (uniforms.extrude) {
    v.y = noise.x;
    n = noise.yz;
  }
  float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * v;
  return {
    .position = p,
    .normal = float3(-n.x, 1, -n.y)
  };
}

float diffuse(float3 n, float3 l, float p) {
  return pow(dot(n, l) * 0.4 + 0.6, p);
}

float specular(float3 n, float3 l, float3 e, float s) {
  float nrm = (s + 8.0) / (PI * 8.0);
  return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

fragment float4 terrainium_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
  float3 c = uniforms.ambientColour;
  c = (normalize(in.normal) + simd_float3(1.0)) / 2.0;
  return float4(c, 1.0);
}
