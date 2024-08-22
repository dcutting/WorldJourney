#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifndef __METAL_VERSION__
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef struct {
  simd_float4x4 mvp;
  float lod;
  simd_float3 eyeLod;
  simd_float3 sunLod;
//  simd_int3 eyeCell;
  simd_float3 ringCenterPositionLod;
  simd_int2 ringCenterCell;
  int baseRingLevel;
  int radius;
  float radiusLod;
  float amplitudeLod;
  float time;
  bool diagnosticMode;
} Uniforms;

#endif /* ShaderTypes_h */
