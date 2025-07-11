#include <metal_stdlib>

using namespace metal;

#ifndef Noise_h
#define Noise_h

float3 fbm2(float2 t0, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeFactor);
float4 fbm3(float3 t0, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeErosionFactor);

typedef struct {
  float3 position;
  float3 normal;
} Gerstner;

float hash31( float3 p );
float3 gHash33( float3 p );
float hash(float2 p);
float4 fbmd_7(float3 x, float f, float a, float l, float p, float o);
float4 fbm(float3 x, int octaves);
Gerstner gerstner(float3 x, float r, float t);
float3 gNoised2(float2 p);
float4 vNoised3(int3 grid, float3 w);
float3 vNoised2(int2 grid, float2 f);

#endif
