#include <metal_stdlib>
#include "InfiniteNoise.h"

using namespace metal;

float4 sampleInf(int3 cubeOrigin, int cubeSize, float3 x, float a, int o) {
  float3 t0 = x;
  float4 terrain = fbmInf3(cubeOrigin, cubeSize, t0, 0.00002, a, o);
  return terrain;
}
