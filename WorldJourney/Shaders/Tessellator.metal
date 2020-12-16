#include <metal_stdlib>
#include "../Common.h"
#include "Terrain.h"
using namespace metal;

constant float f = 1;

struct Sampled {
  float2 xy;
  float w;
  TerrainSample terrain;
};

bool is_off_screen_behind(Sampled s[]) {
  return s[0].w <= 0 && s[1].w <= 0 && s[2].w <= 0 && s[3].w <= 0;
}

bool is_off_screen_left(Sampled s[]) {
  return s[0].xy.x < -f && s[1].xy.x < -f && s[2].xy.x < -f && s[3].xy.x < -f;
}

bool is_off_screen_right(Sampled s[]) {
  return s[0].xy.x > f && s[1].xy.x > f && s[2].xy.x > f && s[3].xy.x > f;
}

bool is_off_screen_up(Sampled s[]) {
  return s[0].xy.y < -f && s[1].xy.y < -f && s[2].xy.y < -f && s[3].xy.y < -f;
}

bool is_off_screen_down(Sampled s[]) {
  return s[0].xy.y > f && s[1].xy.y > f && s[2].xy.y > f && s[3].xy.y > f;
}

kernel void tessellation_kernel(device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float3 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant Terrain &terrain [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]) {
  
  float totalTessellation = 0;
  uint index = pid * 4;

  
  
  // sample corners
  
  Sampled samples[4];
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
    Sampled sampled = {
      .xy = (clip.xy / clip.w) * (clip.w > 0 ? 1 : -1),
      .w = clip.w,
      .terrain = sample
    };
    samples[i] = sampled;
  }
  
  
  
  // frustum culling
  
  if (is_off_screen_behind(samples) ||
      is_off_screen_left(samples) ||
      is_off_screen_right(samples) ||
      is_off_screen_up(samples) ||
      is_off_screen_down(samples)) {
    factors[pid].edgeTessellationFactor[0] = 0;
    factors[pid].edgeTessellationFactor[1] = 0;
    factors[pid].edgeTessellationFactor[2] = 0;
    factors[pid].edgeTessellationFactor[3] = 0;
    factors[pid].insideTessellationFactor[0] = 0;
    factors[pid].insideTessellationFactor[1] = 0;
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
    
    Sampled sA = samples[pointAIndex];
    Sampled sB = samples[pointBIndex];

    // screen space tessellation
    float2 sAxy = sA.xy;
    float2 sBxy = sB.xy;
    sAxy.x = (sAxy.x + 1.0) / 2.0 * uniforms.screenWidth;
    sAxy.y = (sAxy.y + 1.0) / 2.0 * uniforms.screenHeight;
    sBxy.x = (sBxy.x + 1.0) / 2.0 * uniforms.screenWidth;
    sBxy.y = (sBxy.y + 1.0) / 2.0 * uniforms.screenHeight;
    float screenLength = distance(sAxy, sBxy);
    float screenTessellation = screenLength / TESSELLATION_SIDELENGTH;

    float minTessellation = MIN_TESSELLATION;
    float maxTessellation = MAX_TESSELLATION;
    minTessellation = screenTessellation;
    float tessellation = 1;
    
    if (1) {
      // gradient tessellation
      float3 n1 = sA.terrain.gradient;
      float3 n2 = sB.terrain.gradient;
      float g = dot(normalize(n1), normalize(n2));
      g = 1 - ((g + 1.0) / 2.0);
      float t = pow(g, 0.75);
      tessellation = ceil(t * (maxTessellation - minTessellation) + minTessellation);
    } else {
      tessellation = screenTessellation;
    }
    
    tessellation = clamp(tessellation, minTessellation, maxTessellation);
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  
  factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}
