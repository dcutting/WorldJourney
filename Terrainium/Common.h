#ifndef Common_h
#define Common_h

#include <simd/simd.h>

typedef struct {
  matrix_float4x4 modelMatrix;
  matrix_float4x4 viewMatrix;
  matrix_float4x4 projectionMatrix;
  vector_float3 eye;
  vector_float3 ambientColour;
  float drawLevel;
  float level;
  float time;
  int screenWidth;
  int screenHeight;
  int side;
  float radius;
  float lod;
  float radiusLod;
} Uniforms;

typedef struct {
  matrix_float4x4 modelMatrix;
  vector_int3 cubeOrigin;
  int cubeSize;
} QuadUniforms;

#endif
