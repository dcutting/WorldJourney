#ifndef Common_h
#define Common_h

#include <simd/simd.h>

#define TERRAIN_SIZE 32768
#define TERRAIN_HEIGHT 1000
#define PATCH_GRANULARITY 128
#define PATCH_SIDE (TERRAIN_SIZE/PATCH_GRANULARITY)

typedef struct {
    simd_float3 cameraPosition;
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 mvpMatrix;
    simd_float3 lightDirection;
    int renderNormals;
} Uniforms;

typedef struct {
    int octaves;
    float frequency;
    float amplitude;
    float lacunarity;
    float persistence;
} Fractal;

typedef struct {
    float size;
    float height;
    int tessellation;
    Fractal fractal;
} Terrain;

#endif /* Common_h */
