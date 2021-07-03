#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define PATCH_SIDE 19
#define ENVIRONS_SIDE 6
#define USE_SCREEN_TESSELLATION_SIDELENGTH 2
#define MIN_TESSELLATION 2
#define MAX_TESSELLATION 64 // Reduce for iOS
#define USE_NORMAL_MAPS (true)

typedef struct {
  float screenWidth;
  float screenHeight;
  vector_float3 cameraPosition;
  matrix_float4x4 viewMatrix;
  matrix_float4x4 projectionMatrix;
  vector_float3 sunPosition;
  vector_float3 sunColour;
  vector_float3 ambientColour;
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
  float erode;
  int seed;
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

#endif /* Common_h */
