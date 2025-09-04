#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifndef __METAL_VERSION__
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef struct {
  simd_float4x4 mvp;
  simd_float3 fEyeW;
  simd_float3 fSunlightDirectionW;
  simd_float3 fRingCenterEyeOffsetM;
  simd_int2 iRingCenterCellW;
  int iRadiusW;
  int baseRingLevel;
  int maxRingLevel;
  float fTime;
  int diagnosticMode;
} Uniforms;

#endif /* ShaderTypes_h */
