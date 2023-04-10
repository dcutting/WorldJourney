#include <metal_stdlib>

using namespace metal;

#ifndef Noise_h
#define Noise_h

float3 fbm2(int3 cubeStart, int3 cubeStop, float3 t0, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeFactor);
//float3 fbm2(float2 x, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeFactor);
float3 terrain2d(int3 cubeOrigin, int cubeSize, float3 x, int o, float octaveMix);






typedef struct {
  float3 position;
  float3 normal;
} Gerstner;

float hash(float2 p);
float4 fbmd_7(float3 x, float f, float a, float l, float p, int o);
float4 fbm(float3 x, int octaves);
Gerstner gerstner(float3 x, float r, float t);
float3 gNoised2(float2 p);

#endif
