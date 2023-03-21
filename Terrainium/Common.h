//
//  Common.h
//  WorldJourney
//
//  Created by Dan Cutting on 22/12/2022.
//  Copyright © 2022 cutting.io. All rights reserved.
//

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
} Uniforms;

typedef struct {
  matrix_float4x4 modelMatrix;
  vector_int3 cubeOrigin;
  int cubeSize;
} QuadUniforms;

#endif /* Common_h */
