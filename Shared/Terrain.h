#ifndef Terrain_h
#define Terrain_h

#include "Defs.h"

using namespace metal;

typedef struct {
  float depth;
  float height;
  float3 position;
  float3 gradient;
} TerrainSample;

float3 find_unit_spherical_for_template(float3 p, float r, float R, float d_sq, float3 eye);
TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, Terrain terrain, Fractal fractal);
TerrainSample sample_terrain_spherical(float3 unit_spherical, float3 eye, float r, Terrain terrain, Fractal fractal);
TerrainSample sample_ocean_michelic(float3 p, float r, float R, float d_sq, float3 eye, Terrain terrain, Fractal fractal, float time);
float3 applyFog(float3  rgb,      // original color of the pixel
                float distance,   // camera to point distance
                float3  rayDir,   // camera to point vector
                float3  sunDir );  // sun light direction
float3 gammaCorrect(float3 colour);

#endif /* Terrain_h */
