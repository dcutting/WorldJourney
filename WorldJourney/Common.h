#ifndef Common_h
#define Common_h

#include <simd/simd.h>

typedef struct {
    float worldRadius;
    float frequency;
    float amplitude;
    int gridWidth;
    simd_float3 cameraPosition;
    simd_float4x4 viewMatrix;
    simd_float4x4 modelMatrix;
    simd_float4x4 projectionMatrix;
} Uniforms;

#endif /* Common_h */
