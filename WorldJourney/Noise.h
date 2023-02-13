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
float3 fbm2(float2 x, float3 p, float frequency, float amplitude, float lacunarity, float persistence, int startOctaves, int octaves, float octaveMix, float sharpness, float slopeFactor);
float3 terrain2d(float2 x, float3 p, float t, int so, int o, float octaveMix, int supersample);
Gerstner gerstner(float3 x, float r, float t);
float3 gNoised2(float2 p);

#endif
