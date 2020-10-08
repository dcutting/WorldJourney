#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define PATCH_SIDE 200
#define TESSELLATION_SIDELENGTH 2
#define NO_TESSELLATION 0
#define NO_TERRAIN 0

typedef struct {
  float scale;
  float theta;
  float screenWidth;
  float screenHeight;
  vector_float3 cameraPosition;
  matrix_float4x4 modelMatrix;
  matrix_float4x4 viewMatrix;
  matrix_float4x4 projectionMatrix;
  matrix_float4x4 mvpMatrix;
  matrix_float4x4 shadowMatrix;
  vector_float3 sunDirection;
  vector_float3 sunColour;
  float ambient;
  int renderMode;
} Uniforms;

typedef struct {
  int octaves;
  float frequency;
  float amplitude;
  float lacunarity;
  float persistence;
  float warpFrequency;
  float warpAmplitude;
  int erode;
} Fractal;

typedef struct {
  Fractal fractal;
  int tessellation;
  float waterLevel;
  float snowLevel;
  float sphereRadius;
  simd_float3 skyColour;
} Terrain;

#endif /* Common_h */
