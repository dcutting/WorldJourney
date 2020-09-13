#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define TERRAIN_HEIGHT 2000
#define PATCH_SIDE 199
#define TERRAIN_SIZE 1
#define SPHERE_RADIUS 50000
#define TESSELLATION_SIDELENGTH 4

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
} Terrain;

#endif /* Common_h */
