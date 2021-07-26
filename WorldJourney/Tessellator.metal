#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"

using namespace metal;

constant float f = 1;

struct Sampled {
  float2 xy;
  float w;
  TerrainSample terrain;
};

bool is_off_screen_behind(Sampled s[]) {
  for (int i = 0; i < 8; i++) {
    if (s[i].w > 0) {
      return false;
    }
  }
  return true;
}

bool is_off_screen_left(Sampled s[]) {
  for (int i = 0; i < 8; i++) {
    if (s[i].xy.x >= -f) {
      return false;
    }
  }
  return true;
}

bool is_off_screen_right(Sampled s[]) {
  for (int i = 0; i < 8; i++) {
    if (s[i].xy.x <= f) {
      return false;
    }
  }
  return true;
}

bool is_off_screen_up(Sampled s[]) {
  for (int i = 0; i < 8; i++) {
    if (s[i].xy.y >= -f) {
      return false;
    }
  }
  return true;
}

bool is_off_screen_down(Sampled s[]) {
  for (int i = 0; i < 8; i++) {
    if (s[i].xy.y <= f) {
      return false;
    }
  }
  return true;
}

kernel void tessellation_kernel(device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float3 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant Terrain &terrain [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]) {
  
  float totalTessellation = 0;
  uint control_point_index = pid * 4;
  
  float r = terrain.sphereRadius;
  float R = terrain.sphereRadius + (terrain.fractal.amplitude / 2.0);
  float d_sq = length_squared(uniforms.cameraPosition);

  // frustum culling
  
  Sampled corners[8];
  for (int i = 0; i < 4; i++) {
    float3 unit_spherical = find_unit_spherical_for_template(control_points[i + control_point_index],
                                                             r,
                                                             R,
                                                             d_sq,
                                                             uniforms.cameraPosition);
    float4 bottom = float4(unit_spherical * r, 1);
    float4 top = float4(unit_spherical * (terrain.sphereRadius + terrain.fractal.amplitude), 1);
    // TODO: need a way of properly bounding the terrain height - it's not exactly sphere radius + amplitude.

    float4 clipBottom = uniforms.projectionMatrix * uniforms.viewMatrix * bottom;
    Sampled sampledBottom = {
      .xy = (clipBottom.xy / clipBottom.w) * (clipBottom.w > 0 ? 1 : -1),
      .w = clipBottom.w,
      .terrain = TerrainSample()
    };

    float4 clipTop = uniforms.projectionMatrix * uniforms.viewMatrix * top;
    Sampled sampledTop = {
      .xy = (clipTop.xy / clipTop.w) * (clipTop.w > 0 ? 1 : -1),
      .w = clipTop.w,
      .terrain = TerrainSample()
    };

    corners[i*2] = sampledBottom;
    corners[i*2+1] = sampledTop;
  }

  if (is_off_screen_behind(corners) ||
      is_off_screen_left(corners) ||
      is_off_screen_right(corners) ||
      is_off_screen_up(corners) ||
      is_off_screen_down(corners)) {
    factors[pid].edgeTessellationFactor[0] = 0;
    factors[pid].edgeTessellationFactor[1] = 0;
    factors[pid].edgeTessellationFactor[2] = 0;
    factors[pid].edgeTessellationFactor[3] = 0;
    factors[pid].insideTessellationFactor[0] = 0;
    factors[pid].insideTessellationFactor[1] = 0;
    return;
  }
  
  
  
  // sample corners
  
  Sampled samples[4];
  for (int i = 0; i < 4; i++) {
    TerrainSample sample = sample_terrain_michelic(control_points[i + control_point_index],
                                                   r,
                                                   R,
                                                   d_sq,
                                                   uniforms.cameraPosition,
                                                   terrain,
                                                   terrain.fractal);
    float4 clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(sample.position, 1);
    Sampled sampled = {
      .xy = (clip.xy / clip.w) * (clip.w > 0 ? 1 : -1),
      .w = clip.w,
      .terrain = sample
    };
    samples[i] = sampled;
  }
  
  
  
  // tessellation calculations

  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;

    float minTessellation = MIN_TESSELLATION;
    float maxTessellation = MAX_TESSELLATION;
    float tessellation = minTessellation;

    Sampled sA = samples[pointAIndex];
    Sampled sB = samples[pointBIndex];

    // Screenspace tessellation.
    float2 sAxy = sA.xy;
    float2 sBxy = sB.xy;
    sAxy.x = (sAxy.x + 1.0) / 2.0 * uniforms.screenWidth;
    sAxy.y = (sAxy.y + 1.0) / 2.0 * uniforms.screenHeight;
    sBxy.x = (sBxy.x + 1.0) / 2.0 * uniforms.screenWidth;
    sBxy.y = (sBxy.y + 1.0) / 2.0 * uniforms.screenHeight;
    float screenLength = distance(sAxy, sBxy);
    float screenTessellation = screenLength / USE_SCREEN_TESSELLATION_SIDELENGTH;

    // Gradient tessellation.
    float3 n1 = sA.terrain.gradient;
    float3 n2 = sB.terrain.gradient;
    float t = (dot(normalize(n1), normalize(n2))); // TODO: can we also use the second derivative?
    t = 1 - ((t + 1.0) / 2.0);
    t = pow(t, 0.75);
    float gradientTessellation = ceil(t * (MAX_TESSELLATION - MIN_TESSELLATION) + MIN_TESSELLATION);

    // Distance tessellation.
//    float d_pos1 = distance(sA.xy, float2(TERRAIN_PATCH_SIDE/2, TERRAIN_PATCH_SIDE/2));
//    float d_pos2 = distance(sB.xy, float2(TERRAIN_PATCH_SIDE/2, TERRAIN_PATCH_SIDE/2));
//    float d_pos = (d_pos1 + d_pos2) / 2.0;
//    d_pos /= (float)TERRAIN_PATCH_SIDE;
//    d_pos = 1 - d_pos;
//    d_pos = pow(d_pos, 2);
//    tessellation *= d_pos;
    
    minTessellation = screenTessellation;
    tessellation = gradientTessellation;

    // clamp
    tessellation = clamp(tessellation, minTessellation, maxTessellation);
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  
  factors[pid].insideTessellationFactor[0] = (factors[pid].edgeTessellationFactor[1] + factors[pid].edgeTessellationFactor[3]) / 2;
  factors[pid].insideTessellationFactor[1] = (factors[pid].edgeTessellationFactor[0] + factors[pid].edgeTessellationFactor[2]) / 2;
}
