#ifndef Common_h
#define Common_h

#include <simd/simd.h>

typedef struct {
  matrix_float4x4 viewMatrix;
  matrix_float4x4 projectionMatrix;
  int side;
  float lod;
  vector_float3 eyeLod;
  float radiusLod;
  vector_float3 sunLod;
  int screenWidth;
  int screenHeight;
} Uniforms;

typedef struct {
  matrix_float4x4 modelMatrix;
  vector_int3 cubeOrigin;
  int cubeSize;
} QuadUniforms;

#endif
