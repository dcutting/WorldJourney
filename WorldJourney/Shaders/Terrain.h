#ifndef Terrain_h
#define Terrain_h

using namespace metal;

#include "Common.h"

typedef union {
  float4 packed;
  struct {
    float height;
    float3 normal;
  };
} TerrainSample;

typedef struct {
  float3 normal;
  float3 tangent;
  float3 bitangent;
} NormalFrame;

NormalFrame normal_frame(float3 normal);
TerrainSample sample_terrain(float3 p);
float3 find_unit_spherical_for_template(float3 p, float r, float R, float d, float3 eye);
float3 sample_terrain_michelic(float3 p, float r, float R, float d, float f, float a, float3 eye, float4x4 modelMatrix);

#endif /* Terrain_h */
