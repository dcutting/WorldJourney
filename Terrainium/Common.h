#ifndef Common_h
#define Common_h

#include <simd/simd.h>

typedef struct {
//  matrix_float4x4 viewMatrix;
//  matrix_float4x4 projectionMatrix;
//  int side;
  float lod;
  vector_float3 eyeLod;
  float radiusLod;
  float amplitudeLod;
  vector_float3 sunLod;
//  int screenWidth;
//  int screenHeight;
//  float time;
} Uniforms;

typedef struct {
  matrix_float4x4 m;
  matrix_float4x4 mvp;
  float scale;
  vector_int3 cubeOrigin;
  int cubeSize;
  int tessellation[4];
  int tier;
} QuadUniforms;

#endif
