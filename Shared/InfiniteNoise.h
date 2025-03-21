#include <metal_stdlib>

using namespace metal;

#ifndef InfiniteNoise_h
#define InfiniteNoise_h

float4 fbmInf3(int3 cubeOrigin, int cubeSize, float3 x, float freq, float ampl, float octaves, float sharpness, float epsilon);

#endif
