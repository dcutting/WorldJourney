#include <metal_stdlib>
using namespace metal;

#ifndef Noise_h
#define Noise_h

typedef struct {
  float3 position;
  float3 normal;
} Gerstner;

float hash(float2 p);
float4 fbmd_7(float3 x, Terrain terrain, Fractal fractal);
Gerstner gerstner(float3 x, Terrain terrain, Fractal fractal, float time);

#endif
