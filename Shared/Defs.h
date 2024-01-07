//
//  Defs.h
//  WorldJourney
//
//  Created by Dan Cutting on 7/1/2024.
//  Copyright © 2024 cutting.io. All rights reserved.
//

#ifndef Defs_h
#define Defs_h

typedef struct {
  int octaves;
  float frequency;
  float amplitude;
  float lacunarity;
  float persistence;
  float warpFrequency;
  float warpAmplitude;
  float erode;
  int seed;
  int waveCount;
} Fractal;

typedef struct {
  Fractal fractal;
  float waterLevel;
  float snowLevel;
  float sphereRadius;
  simd_float3 groundColour;
  simd_float3 skyColour;
  float shininess;
  float mass;
} Terrain;

#endif /* Defs_h */
