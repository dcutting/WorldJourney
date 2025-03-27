#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/WorldTerrain.h"
#include "../Shared/Terrain.h"
#include "../Shared/Noise.h"
#include "ShaderTypes.h"

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 p, float amplitude, float octaves, float epsilon) {
  float3 cubeOffset = float3(p.x, 0, p.y);
  float4 s = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.000003, 3, 3, 0, 0);
  float ap = amplitude;// * s.x * s.x;
  float frequency = 0.00001;
  float sharpness = 0.7;//clamp(s.x, -1.0, 1.0);
//  float v = ((float)cubeOrigin.x + p.x * cubeSize) * 0.00100;
//  float height = amplitude * (1 + sin(v));
//  float3 deriv(amplitude * cos(v), 0, 0);
//  float4 result = float4(height, deriv.x, deriv.y, deriv.z);
  return
//    result
//    fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.000008, 30000, 4, 0, 0)
  + fbmInf3(cubeOrigin, cubeSize, cubeOffset, frequency, ap, octaves, 0, 0)
  ;
}

float4 calculateDetail(int3 cubeOrigin, int cubeSize, float2 p, float octaves) {
  float3 cubeOffset = float3(p.x, 0, p.y);
  return fbmInf3(cubeOrigin, cubeSize, cubeOffset, 1, 0.1, octaves, -0.4, 0);
}
