#include <metal_stdlib>
#include "../Common.h"
#include "Terrain.h"

using namespace metal;

kernel void height_kernel(constant float3 *control_points [[buffer(0)]],
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
  
  /*
   * Given the current position (p)
   * Need some other vector (b) to form basis of grid (maybe use the same one as michelic?)
   * Technically could be zero, but odds are low and it would only be for a frame or two
   * Project b onto the tangent of the planet directly below position (t) to find u
   * Use cross product of u and normal of p to find other grid direction v
   * Make a grid around these two axes u, v, projected onto sphere
   */
  /*
  float3 b = normalize(float3(0.667893, 0.27821738, 0.87813));  // Arbitrary basis, must be independent of p.
  
  float3 surfaceToCenter = -p;
  float3 surfaceToB = b - p;
  float3 u = normalize(cross(surfaceToCenter, surfaceToB));
  float3 v = normalize(cross(surfaceToCenter, u));
  
  float width = 10;
  float width_2 = width / 2.0;
  int side_2 = side / 2;
  for (int j = 0; j < side; j++) {
    for (int i = 0; i < side; i++) {
      int g = j * side + i;
      
      u * (i - side_2)
      float3 sp = float3(

      float3 np = normalize(sp);
      float3 w = np * terrain.sphereRadius;
      float4 noised = sample_terrain(w, terrain.fractal);

      float sample_height = noised.x;
      float altitude = terrain.sphereRadius + sample_height;
      float3 pp = np * altitude;
      height[g] = pp;
    }
  }*/
}
