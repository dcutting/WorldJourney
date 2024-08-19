#ifndef Common_h
#define Common_h

#include <simd/simd.h>
#include "../Shared/Defs.h"

#define TERRAIN_PATCH_SIDE 49
#define OCEAN_PATCH_SIDE 5
#define ENVIRONS_SIDE 12
#define USE_SCREEN_TESSELLATION_SIDELENGTH 8
#define MIN_TESSELLATION 2
#define MAX_TESSELLATION 64 // Reduce for iOS
#define USE_NORMAL_MAPS (false)

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
  float time;
} Uniforms;

typedef struct {
  vector_float3 coordinate;
  matrix_float4x4 transform;
  float scale;
} InstanceUniforms;

#endif /* Common_h */
