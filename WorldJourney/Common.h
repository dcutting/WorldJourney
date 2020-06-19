#ifndef Common_h
#define Common_h

#include <simd/simd.h>

typedef struct {
    simd_float3 cameraPosition;
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 mvpMatrix;
} Uniforms;

typedef struct {
    float size;
    float frequency;
    float amplitude;
    int tessellation;
} Terrain;

#endif /* Common_h */
