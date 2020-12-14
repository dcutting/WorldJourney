#include <metal_stdlib>
#include "../Common.h"
#include "Terrain.h"
using namespace metal;

constant float f = 1;

bool is_off_screen_behind(float3 s[]) {
  return s[0].z < 0 && s[1].z < 0 && s[2].z < 0 && s[3].z < 0;
}

bool is_off_screen_left(float3 s[]) {
  return s[0].x < -f && s[1].x < -f && s[2].x < -f && s[3].x < -f;
}

bool is_off_screen_right(float3 s[]) {
  return s[0].x > f && s[1].x > f && s[2].x > f && s[3].x > f;
}

bool is_off_screen_up(float3 s[]) {
  return s[0].y < -f && s[1].y < -f && s[2].y < -f && s[3].y < -f;
}

bool is_off_screen_down(float3 s[]) {
  return s[0].y > f && s[1].y > f && s[2].y > f && s[3].y > f;
}

kernel void tessellation_kernel(device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float3 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant Terrain &terrain [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]) {
  
  float totalTessellation = 0;
  float minTessellation = MIN_TESSELLATION;
  uint findex = pid;//(pid.x + pid.y * 200);
  uint index = findex * 4;

  
  
  // sample corners
  
  float3 samples[4];
  float R = terrain.sphereRadius + terrain.fractal.amplitude;
  float d_sq = length_squared(uniforms.cameraPosition);
  for (int i = 0; i < 4; i++) {
    TerrainSample sample = sample_terrain_michelic(control_points[i + index],
                                                   terrain.sphereRadius,
                                                   R,
                                                   d_sq,
                                                   uniforms.cameraPosition,
                                                   terrain.fractal);
    float4 clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(sample.position, 1);
    samples[i] = float3(clip.xy / clip.w, clip.w);
  }
  
  
  
  // frustum culling
  
  if (is_off_screen_behind(samples) ||
      is_off_screen_left(samples) ||
      is_off_screen_right(samples) ||
      is_off_screen_up(samples) ||
      is_off_screen_down(samples)) {
    factors[findex].edgeTessellationFactor[0] = 0;
    factors[findex].edgeTessellationFactor[1] = 0;
    factors[findex].edgeTessellationFactor[2] = 0;
    factors[findex].edgeTessellationFactor[3] = 0;
    factors[findex].insideTessellationFactor[0] = 0;
    factors[findex].insideTessellationFactor[1] = 0;
    return;
  }
  
  
  
  // tessellation calculations

  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;
    
    float2 sA = samples[pointAIndex + index].xy;
    float2 sB = samples[pointBIndex + index].xy;
    
    sA.x = (sA.x + 1.0) / 2.0 * uniforms.screenWidth;
    sA.y = (sA.y + 1.0) / 2.0 * uniforms.screenHeight;
    sB.x = (sB.x + 1.0) / 2.0 * uniforms.screenWidth;
    sB.y = (sB.y + 1.0) / 2.0 * uniforms.screenHeight;
    float screenLength = distance(sA, sB);

    float tessellation = ceil(screenLength / TESSELLATION_SIDELENGTH);
    tessellation = clamp(tessellation, (float)minTessellation, (float)MAX_TESSELLATION);
    
    factors[findex].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  
  factors[findex].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[findex].insideTessellationFactor[1] = totalTessellation * 0.25;
}
