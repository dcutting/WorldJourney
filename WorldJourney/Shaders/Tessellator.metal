#include <metal_stdlib>
#include "../Common.h"
#include "Terrain.h"
using namespace metal;

constant float f = 1;

bool is_off_screen_left(float2 s[]) {
  return s[0].x < -f && s[1].x < -f && s[2].x < -f && s[3].x < -f;
}

bool is_off_screen_right(float2 s[]) {
  return s[0].x > f && s[1].x > f && s[2].x > f && s[3].x > f;
}

bool is_off_screen_up(float2 s[]) {
  return s[0].y < -f && s[1].y < -f && s[2].y < -f && s[3].y < -f;
}

bool is_off_screen_down(float2 s[]) {
  return s[0].y > f && s[1].y > f && s[2].y > f && s[3].y > f;
}

uint controlPointIndex(int x, int y) {
  return y * (PATCH_SIDE+1) + x;
}

kernel void tessellation_kernel(device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float3 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant Terrain &terrain [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]) {
  
  float totalTessellation = 0;
  float minTessellation = MIN_TESSELLATION;
  uint findex = pid;

  
  
  // sample corners
  float2 samples[4];
  
  {
    uint x = pid % PATCH_SIDE;
    uint y = pid / PATCH_SIDE;
    float R = terrain.sphereRadius + terrain.fractal.amplitude;
    float d_sq = length_squared(uniforms.cameraPosition);
    
    uint index = controlPointIndex(x,y);
    TerrainSample sample = sample_terrain_michelic(control_points[index],
                                                   terrain.sphereRadius,
                                                   R,
                                                   d_sq,
                                                   uniforms.cameraPosition,
                                                   terrain.fractal);
    float4 clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(sample.position, 1);
    samples[0] = clip.xy / clip.w;

    // TODO
    
    index = controlPointIndex(x+1,y);
    sample = sample_terrain_michelic(control_points[index],
                                                   terrain.sphereRadius,
                                                   R,
                                                   d_sq,
                                                   uniforms.cameraPosition,
                                                   terrain.fractal);
    clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(sample.position, 1);
    samples[1] = clip.xy / clip.w;

    index = controlPointIndex(x+1,y+1);
    sample = sample_terrain_michelic(control_points[index],
                                                   terrain.sphereRadius,
                                                   R,
                                                   d_sq,
                                                   uniforms.cameraPosition,
                                                   terrain.fractal);
    clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(sample.position, 1);
    samples[2] = clip.xy / clip.w;

    index = controlPointIndex(x,y+1);
    sample = sample_terrain_michelic(control_points[index],
                                                   terrain.sphereRadius,
                                                   R,
                                                   d_sq,
                                                   uniforms.cameraPosition,
                                                   terrain.fractal);
    clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(sample.position, 1);
    samples[3] = clip.xy / clip.w;
  }
  
  
  // frustum culling
  
  if (is_off_screen_left(samples) ||
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
    
    float2 sA = samples[pointAIndex];
    float2 sB = samples[pointBIndex];
    
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