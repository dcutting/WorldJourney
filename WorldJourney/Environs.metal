#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"

using namespace metal;

kernel void environs_kernel(constant float3 *control_points [[buffer(0)]],
                          constant float3 &p [[buffer(1)]],
                          constant Terrain &terrain [[buffer(2)]],
                          volatile device simd_float3 *mesh [[buffer(3)]],
                          uint pid [[thread_position_in_grid]]) {
  
  float r = terrain.sphereRadius;
  float R = terrain.sphereRadius + (terrain.fractal.amplitude / 2.0);
  float d_sq = length_squared(p);

  TerrainSample sampled = sample_terrain_michelic(control_points[pid],
                                                  r,
                                                  R,
                                                  d_sq,
                                                  p,
                                                  terrain.fractal);
  mesh[pid] = sampled.position;
}
