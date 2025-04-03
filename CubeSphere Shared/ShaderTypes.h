#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifndef __METAL_VERSION__
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef struct {
  simd_float4x4 mvp;
  simd_float3 eye;
  simd_float3 sun;
  simd_float3 ringCenterEyeOffset;
  simd_int2 ringCenterCell;
  int baseRingLevel;
  int maxRingLevel;
  int radius;
  float amplitude;
  float time;
  bool diagnosticMode;
} Uniforms;

#endif /* ShaderTypes_h */
