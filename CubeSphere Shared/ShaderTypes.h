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
  simd_int2 iRingCenterW;
  simd_int3 iEyeW;
  simd_float2 fRingCenterOffsetM;
  int iRadiusW;
  int baseRingLevel;
  int maxRingLevel;
  float fTime;
  int diagnosticMode;
  int mappingMode;
} Uniforms;

#endif /* ShaderTypes_h */
