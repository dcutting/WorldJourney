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

//constant float PI = 3.14159;

struct VertexOut {
  float4 position [[position]];
  float3 worldPosition;
  float3 normal;
//  float fractOctaves;
//  int octaves;
//  float octaveMix;
//  float sha;
//  float worldDiff;
};

//float softshadow(float3 ro, float3 rd, float mint, float maxt, float maxHeight, int maxSteps, float k, int octaves, float octaveMix) {
//  float res = 1.0;
//  for (float t = mint; t < maxt && maxSteps > 0;) {
//    float3 wp = ro + rd*t;
//    if (wp.y > maxHeight) { break; }
//    float h = wp.y - terrain2d(wp.xz, octaves, octaveMix).x;
//    if (h < 0.01) {
//      return 0.0;
//    }
//    res = min(res, k*h/t);
//    t += h;
//    maxSteps--;
//  }
//  return res;
//}

//constant float mint = 0.05;
//constant float maxt = 1000;
//constant int maxSteps = 2000;
//constant float maxHeight = 10;
//constant float k = 32;

struct ControlPoint {
  float4 position [[attribute(0)]];
};

float adaptiveOctaves(float dist, int maxOctaves, float minDist, float maxDist) {
  int minOctaves = 0;
  float factor = smoothstep(minDist, maxDist, dist);
  
  float i = dist;
  float A = maxDist;
  float B = minDist;
  float N = A - B;
  float v2 = i / N;
  v2 = pow(v2, 0.4);

  factor = saturate(v2);

  float detailFactor = 1.0 - (factor * 0.99 + 0.001);

  float fractOctaves = (maxOctaves - minOctaves) * detailFactor + minOctaves;
  
  return fractOctaves;
}

float worldDiffForScreenSpace(constant Uniforms &uniforms, float4 wp, int pixels) {

  float min = 0;
  float max = 10;
  float candidate = 5;
  for (int i = 0; i < 100; i++) {
    float4 wp2 = float4(wp.xyz / wp.w + float3(0, candidate, 0), 1);
    float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * wp;
    float4 p2 = uniforms.projectionMatrix * uniforms.viewMatrix * wp2;
    float nDiff = abs(p2.y/p2.w - p.y/p.w);
    int ssDiff = int(nDiff * uniforms.screenHeight);
    if (ssDiff == pixels) {
      break;
    }
    if (ssDiff > pixels) {
      max = candidate;
      candidate = (candidate - min) / 2.0 + min;
    } else {
      min = candidate;
      candidate = (max - candidate) / 2.0 + candidate;
    }
  }
  return candidate;
}

[[patch(quad, 4)]]
vertex VertexOut terrainium_vertex(patch_control_point<ControlPoint> control_points [[stage_in]],
                                   uint patchID [[patch_id]],
                                   float2 patch_coord [[position_in_patch]],
                                   constant Uniforms &uniforms [[buffer(1)]]
                                   ) {
  float patchu = patch_coord.x;
  float patchv = patch_coord.y;
  float2 top = mix(control_points[0].position.xy, control_points[1].position.xy, patchu);
  float2 bottom = mix(control_points[3].position.xy, control_points[2].position.xy, patchu);
  float2 vid = mix(top, bottom, patchv);

  float4 v = float4(vid.x, 0, vid.y, 1.0);
  float4 wp = uniforms.modelMatrix * v;
  float dist = distance(wp.xyz, uniforms.eye);

  float fractOctaves = adaptiveOctaves(dist, 5, 0.1, 200);
  
  float octaveMix = fract(fractOctaves);
  int octaves = ceil(fractOctaves);
  float3 noise = terrain2d(wp.xz, octaves, octaveMix);
  float2 dv(0);
  if (uniforms.drawLevel) {
    wp.y = uniforms.level;
  } else {
    wp.y = noise.x;
    dv = noise.yz;
  }
  float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * wp;

//  float sha = 1.0;
//  float3 sun(100, 30, 100);
//  float3 ro = wp.xyz;
//  float3 rd = normalize(sun - wp.xyz);
//  sha = softshadow(ro, rd, mint, maxt, maxHeight, maxSteps, k, octaves, 1.0);
  
  return {
    .position = p,
    .worldPosition = wp.xyz / wp.w,
    .normal = float3(-dv.x, 1, -dv.y)
//    .fractOctaves = fractOctaves,
//    .octaves = octaves,
//    .octaveMix = octaveMix,
//    .sha = sha,
//    .worldDiff = pfe7
  };
}

float3 applyFog(float3  rgb,      // original color of the pixel
                float distance,   // camera to point distance
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
  float dist = distance(in.worldPosition, uniforms.eye);
  
  float fractOctaves = adaptiveOctaves(dist, 16, 0.1, 200);
  float octaveMix = fract(fractOctaves);
  int octaves = ceil(fractOctaves);

  float3 noise = terrain2d(in.worldPosition.xz, octaves, octaveMix);
  float3 n = normalize(float3(-noise.y, 1, -noise.z));

  float3 ragged = fbm2(in.worldPosition.xz + 20*noise.x, 0.13, 1, 2, 0.5, 2, 1, 0, 0);
  float raggedness = ragged.x * 0.5 + 0.5;
  
  float3 sun(100, 30, 100);
  float3 light = normalize(sun - in.worldPosition);
  float sunStrength = saturate(dot(n, light));
  
  float sha = 1;//in.sha;
//  float3 ro = in.worldPosition;
//  float3 rd = normalize(sun - in.worldPosition);
//  sha = softshadow(ro, rd, mint, maxt, maxHeight, maxSteps, k, octaves, in.octaveMix);

  float3 sunColour = float3(1.64,1.27,0.99);
  float3 lin = sunStrength;
  lin *= sunColour;
  lin *= pow(float3(sha),float3(1.0,1.2,1.5));
  
  float3 snow(1.0);
  float3 rock(0.21, 0.2, 0.2);
  float3 strata[] = {float3(0.3, 0.21, 0.21), float3(0.13, 0.1, 0.1)};

  float upness = (dot(n, float3(0,1,0)));
  float snowiness = smoothstep(0.94, 0.95, upness);
  float steepness = smoothstep(0.97, 0.99, upness);
  
  int band = int(floor((in.worldPosition.y + raggedness) * 10)) % 2;
  float3 strataColour = strata[band];
  float3 material = mix(strataColour, rock, steepness);

  material *= lin;
  snow *= sunStrength;
  
  float heightiness = smoothstep(0.8, 0.81, in.worldPosition.y + raggedness);
  
  float snowish = snowiness * heightiness;
  
  float shininess = mix(0, 1, snowish);
  
  float3 colour = mix(material, snow, snowish);

  float3 eye2World = normalize(in.worldPosition - uniforms.eye);
  float3 world2Sun = normalize(sun - in.worldPosition);
  float3 sun2Eye = normalize(uniforms.eye - sun);

  float3 rWorld2Sun = reflect(world2Sun, n);
  float spec = dot(eye2World, rWorld2Sun);
  float specStrength = saturate(shininess * spec);
  specStrength = pow(specStrength, 10.0);
  colour += sunColour * specStrength;
  
  colour = applyFog(colour, dist, eye2World, sun2Eye);
  colour = pow(colour, float3(1.0/2.2));
  
//  colour = n / 2.0 + 0.5;
//  colour = float3(1);
  
  return float4(colour, 1.0);
}
