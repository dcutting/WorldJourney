#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define NEAR_CLIP 0.5
#define PATCH_SIDE 100
#define TESSELLATION_SIDELENGTH 4
#define MIN_TESSELLATION 1
#define MAX_TESSELLATION 16 // Reduce for iOS

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
  int erode;
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
