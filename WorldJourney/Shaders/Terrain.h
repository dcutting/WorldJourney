#ifndef Terrain_h
#define Terrain_h

#include "Common.h"

struct NormalFrame {
  float3 normal;
  float3 tangent;
  float3 bitangent;
};

float4 sample_terrain(float3 p, Fractal fractal);
float get_height(float4 sample);
float3 get_normal(float4 sample);
NormalFrame normal_frame(float3 normal);

#endif /* Terrain_h */
