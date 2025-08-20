#include <metal_stdlib>
#include "../Shared/GridPosition.h"

using namespace metal;

#ifndef InfiniteNoise_h
#define InfiniteNoise_h

float4 fbmRegular(GridPosition initial, float frequency, float octaves);
float4 fbmSquared(GridPosition initial, float frequency, float octaves);
float4 fbmCubed(GridPosition initial, float frequency, float octaves);
float4 fbmEroded(GridPosition initial, float frequency, float octaves);
float4 swissTurbulence(GridPosition initial, float frequency, float octaves);
float4 jordanTurbulence(GridPosition initial, float frequency, float octaves);

//template <typename Func>
float4 fbmWarped(GridPosition initial, float frequency, float octaves, float warpFrequency, float warpOctaves, float warpFactor);//, FuncWrapper<Func> wrapper);

float4 fbmInf3(int3 cubeOrigin, int cubeSize, float3 x, float freq, float ampl, float octaves, float sharpness, float epsilon);

#endif
