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

#endif
