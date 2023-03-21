#include <metal_stdlib>

using namespace metal;

#ifndef InfiniteNoise_h
#define InfiniteNoise_h

float gradient_noise_inner(int3 cube_pos0, int3 cube_pos1, float3 t0, float3 t1);

#endif
