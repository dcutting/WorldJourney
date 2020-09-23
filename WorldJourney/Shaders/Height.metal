#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
using namespace metal;



/** height kernel */

kernel void eden_height(constant Uniforms &uniforms [[buffer(0)]],
                        constant Terrain &terrain [[buffer(1)]],
                        constant float3 &p [[buffer(2)]],
                        volatile device float *height [[buffer(3)]],
                        volatile device float3 *normal [[buffer(4)]],
                        uint gid [[thread_position_in_grid]]) {
  float3 w = (uniforms.modelMatrix * float4(p, 1)).xyz;
  float4 sample = sample_terrain(w, terrain.fractal);
  *height = get_height(sample);
  *normal = get_normal(sample); // TODO: is this right?
}
