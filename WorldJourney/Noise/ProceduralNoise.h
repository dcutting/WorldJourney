#include <metal_stdlib>
using namespace metal;

#ifndef ProceduralNoise_h
#define ProceduralNoise_h

float fbm_texture_noise_2d(float2 st, Fractal fractal, texture2d<float> noiseMap);

float hash(float2 p);
float3 value_noised_2d(float2 p);
float3 fbm_value_noised_2d(float2 x, int octaves);

float4 simplex_noised_3d(float3 x);
float4 fractal_simplex_noised_3d(float3 p, float f, float a);
float4 fbm_simplex_noised_3d(float3 x, Fractal fractal);
float4 fbmd_7(float3 x, Fractal fractal);

#endif
