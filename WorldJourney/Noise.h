#include <metal_stdlib>
using namespace metal;

#ifndef Noise_h
#define Noise_h

float hash(float2 p);
float4 fbmd_7(float3 x, Fractal fractal);

#endif
