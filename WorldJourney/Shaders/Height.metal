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
  float3 w = normalize(p) * terrain.sphereRadius;
  float4 noised = sample_terrain(w, terrain.fractal);
  *height = terrain.sphereRadius + noised.x;
  *normal = sphericalise_flat_gradient(noised.yzw, terrain.fractal.amplitude, w);
}
