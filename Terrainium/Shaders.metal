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
  int octaves;
  float octaveMix;
  float sha;
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

float softshadow(float3 ro, float3 rd, float mint, float maxt, float maxHeight, int maxSteps, float k, int octaves, float octaveMix) {
  float res = 1.0;
  for (float t = mint; t < maxt && maxSteps > 0;) {
    float3 wp = ro + rd*t;
    if (wp.y > maxHeight) { break; }
    float h = wp.y - terrain2d(wp.xz, float3(0), 0, 0, octaves, octaveMix, 0).x;
    if (h < 0.01) {
      return 0.0;
    }
    res = min(res, k*h/t);
    t += h;
    maxSteps--;
  }
  return res;
}

constant float mint = 0.05;
constant float maxt = 1000;
constant int maxSteps = 2000;
constant float maxHeight = 10;
constant float k = 32;

struct ControlPoint {
  float4 position [[attribute(0)]];
};

float adaptiveOctaves(float dist, int minOctaves, int maxOctaves, float minDist, float maxDist) {
  float factor = smoothstep(minDist, maxDist, dist);
  
  float i = dist;
  float A = maxDist;
  float B = minDist;
  float N = A - B;
  float v2 = i / N;
  v2 = v2 * v2;

  factor = saturate(v2);

  float detailFactor = 1.0 - (factor * 0.99 + 0.001);

  float fractOctaves = (maxOctaves - minOctaves) * detailFactor + minOctaves;
  
  return fractOctaves;
}

[[patch(quad, 4)]]
vertex VertexOut terrainium_vertex(patch_control_point<ControlPoint> control_points [[stage_in]],
                                   uint patchID [[patch_id]],
                                   float2 patch_coord [[position_in_patch]],
//                                   constant float2 *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]]
//                                   uint id [[vertex_id]]
                                   ) {
//  float2 vid = vertices[id];
  float patchu = patch_coord.x;
  float patchv = patch_coord.y;
  float2 top = mix(control_points[0].position.xy, control_points[1].position.xy, patchu);
  float2 bottom = mix(control_points[3].position.xy, control_points[2].position.xy, patchu);
  float2 vid = mix(top, bottom, patchv);

  float4 v = float4(vid.x, 0, vid.y, 1.0);
  float4 wp = uniforms.modelMatrix * v;
  float dist = distance(wp.xyz, uniforms.eye);

  float fractOctaves = adaptiveOctaves(dist, 1, 4, 0.1, 400);
  
  float octaveMix = fract(fractOctaves);
  int octaves = ceil(fractOctaves);
  float3 noise = terrain2d(wp.xz, float3(0), 0, 0, octaves, octaveMix, 0);
  float2 dv(0);
  if (uniforms.drawLevel) {
    wp.y = uniforms.level;
  } else {
    wp.y = noise.x;
    dv = noise.yz;
  }
  float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * wp;
  float sha = 1.0;

//  float3 sun(sin(uniforms.time)*100, 30, cos(uniforms.time)*100);
  float3 sun(100, 30, 100);
  float3 ro = wp.xyz;
  float3 rd = normalize(sun - wp.xyz);
//  sha = softshadow(ro, rd, mint, maxt, maxHeight, maxSteps, k, octaves, 1.0);
  
  return {
    .position = p,
    .worldPosition = wp.xyz,  // TODO: w?
    .normal = float3(-dv.x, 1, -dv.y),
    .octaves = octaves,
    .octaveMix = octaveMix,
    .sha = sha
  };
}

float3 applyFog( float3  rgb,      // original color of the pixel
               float distance, // camera to point distance
               float3  rayDir,   // camera to point vector
               float3  sunDir )  // sun light direction
{
  float b = 0.001;
    float fogAmount = 1.0 - exp( -distance*b );
    float sunAmount = max( dot( rayDir, sunDir ), 0.0 );
    float3  fogColor  = mix( float3(0.5,0.6,0.7), // bluish
                           float3(1.0,0.9,0.7), // yellowish
                           pow(sunAmount,8.0) );
    return mix( rgb, fogColor, fogAmount );
}

fragment float4 terrainium_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
  float3 material(0.2);
  float3 a = 0.0;//uniforms.ambientColour;
  float3 n = normalize(in.normal);
  float dist = distance(in.worldPosition, uniforms.eye);
  bool perPixelNormals = true;
  if (perPixelNormals) {
    
    float fractOctaves = adaptiveOctaves(dist, 0, 6, 0.1, 300);
    float octaveMix = fract(fractOctaves);
    int octaves = ceil(fractOctaves);
    
    float3 p(in.worldPosition.y, -in.normal.x, -in.normal.z);
    float3 noise = fbm2(in.worldPosition.xz, float3(0), 0.7, 0.4, 2, 0.5, 0, octaves, octaveMix, 0, 0);

    float fractOctaves2 = adaptiveOctaves(dist, 0, 4, 0.01, 20);
    float octaveMix2 = fract(fractOctaves2);
    int octaves2 = ceil(fractOctaves2);
    
    float3 noise2 = fbm2(in.worldPosition.xz, float3(0), 40, 0.01, 2, 0.5, 0, octaves2, octaveMix2, 0, 0);
// TODO: bug in normal calculation
    float3 dv(+noise.y + noise2.y - in.normal.x, 1, +noise.z + noise2.z - in.normal.z);
//    dv += in.normal;
    n = normalize(dv);
  }
  float t = uniforms.time;
//  float3 sun(100*sin(t), abs(100*cos(t)), 0);
    float3 sun(100, 30, 100);
//    float3 sun(sin(uniforms.time)*100, 40, cos(uniforms.time)*100);
  float3 light = normalize(sun - in.worldPosition);
  float sunlight = saturate(dot(n, light));
  
  float3 ro = in.worldPosition;
  float3 rd = normalize(sun - in.worldPosition);
  int octaves = in.octaves;

  float sha = in.sha;
//  sha = softshadow(ro, rd, mint, maxt, maxHeight, maxSteps, k, octaves, in.octaveMix);

  float3 lin = sunlight;
  lin *= float3(1.64,1.27,0.99);
  lin *= pow(float3(sha),float3(1.0,1.2,1.5));

  float3 colour = material * lin;
  colour = applyFog(colour, dist, normalize(in.worldPosition - uniforms.eye), normalize(uniforms.eye - sun));
  colour = pow(colour, float3(1.0/2.2));
  
//  colour = n / 2.0 + 0.5;
//  colour = float3(1);
  
  return float4(colour, 1.0);
}
