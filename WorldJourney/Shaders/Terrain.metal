#include <metal_stdlib>
#include <simd/simd.h>
#include "Terrain.h"
#include "Common.h"
#include "../Noise/ProceduralNoise.h"

using namespace metal;



float4 sample_terrain(float3 p, Fractal fractal) {
  return simplex_noised_3d(p);
}

float get_height(float4 sample) {
  return sample.x;
}

float3 get_normal(float4 sample) {
  return sample.yzw;
}

NormalFrame normal_frame(float3 normal) {
  // TODO: fix this.
  return {
    .normal = normal,
    .tangent = float3(1, 0, 0),
    .bitangent = float3(0, 0, 1)
  };
}
