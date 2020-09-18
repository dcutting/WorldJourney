#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define PATCH_SIDE 31
#define TESSELLATION_SIDELENGTH 1

typedef struct {
    float scale;
    float screenWidth;
    float screenHeight;
    simd_float3 cameraPosition;
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 mvpMatrix;
    simd_float3 lightDirection;
    int renderMode;
} Uniforms;

typedef struct {
    int octaves;
    float frequency;
    float amplitude;
    float lacunarity;
    float persistence;
} Fractal;

typedef struct {
    int tessellation;
    Fractal fractal;
    float waterLevel;
    float snowLevel;
    float sphereRadius;
} Terrain;

#endif /* Common_h */
