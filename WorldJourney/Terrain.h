#ifndef Terrain_h
#define Terrain_h

using namespace metal;

#include "Common.h"

typedef struct {
  float depth;
  float height;
  float3 position;
  float3 gradient;
} TerrainSample;

float3 find_unit_spherical_for_template(float3 p, float r, float R, float d_sq, float3 eye);
TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, Terrain terrain, Fractal fractal);
TerrainSample sample_ocean_michelic(float3 p, float r, float R, float d_sq, float3 eye, Terrain terrain, Fractal fractal, float time);
float3 sphericalise_flat_gradient(float3 gradient, float amplitude, float3 surfacePoint);

#endif /* Terrain_h */
