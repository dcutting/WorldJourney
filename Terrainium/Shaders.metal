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

float3 prepMixer(float3 x) {
  return saturate((x + 1.0) / 2.0);
}

float3 combine(float3 a, float3 b, float m, float p, float q) {
  float3 terrain = b;
  if (m < p) {
    terrain = a;
  } else if (m < q) {
    terrain = mix(a, b, (m - p) / (q - p));
  }
  return terrain;
}

//float3 terrain2d(float2 x, float t) {
//  float3 basic = fbm2(x, 2.5, 0.15, 1.5, 0.2, 4, sin(t));
//  float3 enhanced = basic * pow();
//  return enhanced;
//
//  float3 mixer0 = prepMixer(fbm2(x, 1, 1, 1.1, 0.8, 1, 0));
//  float3 mixer1 = prepMixer(fbm2(x, 2.5, 2, 1.8, 0.3, 5, 0));
//  float3 mixer2 = prepMixer(fbm2(mixer0.x, 1, 2, 1.4, 1, 2, 0));
//  float3 mixer3 = prepMixer(fbm2(x, 0.2, 3, 1.1, 0.8, 5, 0));
//  float3 plains = fbm2(x, 3, 0.02, 1.1, 0.3, 5, 0);
//  float3 dunes = fbm2(x, 10, 0.01, 1.5, 0.2, 3, 0);
//  float3 craters = fbm2(mixer0.x, 1, 0.1, 0.5, 0.1, 2, 0);
//  float3 mountains = fbm2(x, 2, 0.1, 1.8, 0.3, 10, 0);
//  float3 terrain = combine(plains, mountains, mixer0.x, 0.4, 0.6);
//  = mix(plains, mountains, saturate(mixer1.x));
//  float3 terrain = mix(mix(plains, dunes, saturate(mixer2.x)), mountains, saturate(mixer3.x));
//}

vertex VertexOut terrainium_vertex(constant float2 *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   uint id [[vertex_id]]) {
  float2 vid = vertices[id];
  float4 v = float4(vid.x, 0, vid.y, 1.0);
  float4 wp = uniforms.modelMatrix * v;
  float3 noise = terrain2d(wp.xz + float2(0, -uniforms.time*20), 1.5, 40, uniforms.time);
  float2 dv(0);
  if (uniforms.drawLevel) {
    wp.y = uniforms.level;
  } else {
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
  float t = uniforms.time;
//  float3 sun(100*sin(t), abs(100*cos(t)), 0);
  float3 sun(100, 100, 100);
  float3 light = normalize(sun - in.worldPosition);
  float d = saturate(dot(n, light)) * 0.5;
  float3 c = saturate(a + d);
//  c = (normalize(in.normal) + simd_float3(1.0)) / 2.0;
  return float4(c, 1.0);
}
