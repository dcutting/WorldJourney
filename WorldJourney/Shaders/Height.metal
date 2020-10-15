#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"

using namespace metal;

kernel void height_kernel(constant Uniforms &uniforms [[buffer(0)]],
                          constant Terrain &terrain [[buffer(1)]],
                          constant float3 &p [[buffer(2)]],
                          volatile device float *height [[buffer(3)]],
                          volatile device float3 *normal [[buffer(4)]],
                          uint gid [[thread_position_in_grid]]) {
  float3 np = normalize(p);
  float3 w = np * terrain.sphereRadius;
  float4 noised = sample_terrain(w, terrain.fractal);

  float sample_height = noised.x;
  float altitude = terrain.sphereRadius + sample_height;
  float3 scaled_gradient = noised.yzw / altitude;

  *height = altitude;
  *normal = sphericalise_flat_gradient(scaled_gradient, terrain.fractal.amplitude, np);
}
