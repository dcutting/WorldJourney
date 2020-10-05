#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define PATCH_SIDE 200
#define TESSELLATION_SIDELENGTH 3
#define NO_TESSELLATION 0
#define NO_TERRAIN 0

typedef struct {
  float scale;
  float theta;
  float screenWidth;
  float screenHeight;
  simd_float3 cameraPosition;
  simd_float4x4 modelMatrix;
  simd_float4x4 viewMatrix;
  simd_float4x4 projectionMatrix;
  simd_float4x4 mvpMatrix;
  simd_float3 sunDirection;
  simd_float3 sunColour;
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
