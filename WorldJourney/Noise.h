#include <metal_stdlib>

using namespace metal;

#ifndef Noise_h
#define Noise_h

typedef struct {
  float3 position;
  float3 normal;
} Gerstner;

float hash(float2 p);
float4 fbmd_7(float3 x, float f, float a, float l, float p, int o);
float4 fbm(float3 x, int octaves);
float3 fbm2(float2 x, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeFactor);
float3 terrain2d(float2 x, float t, int o, float octaveMix);
Gerstner gerstner(float3 x, float r, float t);

#endif
