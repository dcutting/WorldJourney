#ifndef Terrain_h
#define Terrain_h

using namespace metal;

#include "Common.h"

typedef struct {
  float height;
  float3 position;
  float3 gradient;
} TerrainSample;

//typedef struct {
//  float3 normal;
//  float3 tangent;
//  float3 bitangent;
//} NormalFrame;
//
//NormalFrame normal_frame(float3 normal);
//TerrainSample sample_terrain(float3 p);

TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, float4x4 modelMatrix, Fractal fractal);

#endif /* Terrain_h */
