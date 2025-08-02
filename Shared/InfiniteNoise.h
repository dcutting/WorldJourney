#include <metal_stdlib>
#include "../Shared/GridPosition.h"

using namespace metal;

#ifndef InfiniteNoise_h
#define InfiniteNoise_h

float4 fbmRegular(GridPosition initial, float frequency, float octaves);
float4 fbmSquared(GridPosition initial, float frequency, int octaves);
float4 fbmCubed(GridPosition initial, float frequency, int octaves);
float4 eroded(GridPosition initial, float frequency, float octaves);
float4 swissTurbulence(GridPosition initial, float frequency, int octaves);
float4 jordanTurbulence(GridPosition initial, float frequency, int octaves);
float4 gemini(GridPosition initial, float frequency, uint octaves);

#endif
