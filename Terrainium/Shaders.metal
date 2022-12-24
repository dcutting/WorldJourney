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
  float3 worldPosition;
  float3 normal;
};

vertex VertexOut terrainium_vertex(constant float2 *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   uint id [[vertex_id]]) {
  float2 vid = vertices[id];
  float4 v = float4(vid.x, 0, vid.y, 1.0);
  float4 wp = uniforms.modelMatrix * v;
  float3 noise = fbm2(wp.xz, 2.5, 0.3, 1.4, 0.3, 4);
  float2 dv(0);
  if (uniforms.extrude) {
    wp.y = noise.x;
    dv = noise.yz;
  }
  float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * wp;
  return {
    .position = p,
    .worldPosition = wp.xyz,
    .normal = float3(-dv.x, 1, -dv.y)
  };
}

fragment float4 terrainium_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
  float3 a = uniforms.ambientColour;
  float3 n = normalize(in.normal);
  float t = uniforms.time * 4;
  float3 sun(10, 10, 10);
  float3 light = normalize(sun - in.worldPosition);
  float d = saturate(dot(n, light));
  float3 c = saturate(a + d);
  c = (normalize(in.normal) + simd_float3(1.0)) / 2.0;
  return float4(c, 1.0);
}
