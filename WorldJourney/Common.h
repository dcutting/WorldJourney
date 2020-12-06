#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define PATCH_SIDE 30
#define TESSELLATION_SIDELENGTH 6
#define MIN_TESSELLATION 16
#define MAX_TESSELLATION 16 // Reduce for iOS

typedef struct {
  float screenWidth;
  float screenHeight;
  vector_float3 cameraPosition;
  matrix_float4x4 viewMatrix;
  matrix_float4x4 projectionMatrix;
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
  float shininess;
  float mass;
} Terrain;

#endif /* Common_h */
