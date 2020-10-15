#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define PATCH_SIDE 20
#define TESSELLATION_SIDELENGTH 2
#if __METAL_MACOS__
  #define MAX_TESSELLATION 64
#else
  #define MAX_TESSELLATION 16
#endif

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
  vector_float3 sunDirection;
  vector_float3 sunPosition;
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
  float waterLevel;
  float snowLevel;
  float sphereRadius;
  simd_float3 groundColour;
  simd_float3 skyColour;
} Terrain;

#endif /* Common_h */
