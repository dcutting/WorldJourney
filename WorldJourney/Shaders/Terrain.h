#ifndef Terrain_h
#define Terrain_h

using namespace metal;

#include "Common.h"

typedef struct {
  float height;
  float3 position;
  float3 gradient;
} TerrainSample;

float4 sample_terrain(float3 p, Fractal fractal);
TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, float4x4 modelMatrix, Fractal fractal);
float3 sphericalise_flat_gradient(float3 gradient, float amplitude, float3 surfacePoint);

#endif /* Terrain_h */