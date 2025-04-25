#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/WorldTerrain.h"
#include "../Shared/Terrain.h"
#include "../Shared/Noise.h"
#include "ShaderTypes.h"

float4 linear(float4 input) {
  return input;
}

float4 x3(float4 g) {
  // d/dx (f(g(x)) = f'(g(x)) · g'(x)
  // f(x) = x^3
  // f'(x) = 3x^2
  float x = g.x * g.x * g.x;
  float3 d = 3.0 * pow(g.x, 2.0) * g.yzw;
  return float4(x, d);
}

float4 x5(float4 g) {
  float f = g.x;
  float u = f*f*f*(f*(f*6.0-15.0)+10.0);
  float3 d = 30.0*f*f*(f*(f-2.0)+1.0) * g.yzw;
  return float4(u, d);
}

float4 x5t(float4 g, float2 shape[], int shapeCount) {
  if (g.x < shape[0].x) { return float4(shape[0].y, 0, 1, 0); }
  if (g.x > shape[shapeCount-1].x) { return float4(shape[shapeCount-1].y, 0, 1, 0); }
  float2 p, q;
  for (int i = 1; i < shapeCount; i++) {
    if (shape[i].x > g.x) {
      p = shape[i-1]; q = shape[i];
      break;
    }
  }

  float wd = 1.0 / (q.x - p.x);
  float4 gp = float4((g.x - p.x) * wd, g.yzw);
  float4 f = x5(gp);
  f.yzw /= wd;
  float hd = (q.y - p.y);
  f *= hd;
  f.x += p.y;
  return f;
}

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 p, float amplitude, float octaves, float epsilon) {
  float3 cubeOffset = float3(p.x, 0, p.y);
  float4 continentalness = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.0000005, 1, 2, 0, 0);
  float4 erosionness = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.000005, 1, 5, 0, 0);
  float4 peaksness = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.00005, 1, 16, 0.5, 0);

  float2 continentalShape[] = {
    //    float2(-1, 1),
    //    float2(-0.95, -1),
    //    float2(-0.3, -0.9),
    //    float2(-0.25, -0.15),
    //    float2(-0.1, -0.15),
//        float2(0, 0),
//        float2(0, 1),
        float2(0.05, 0.05),
    //    float2(0.5, 0.9),
//        float2(0, 1),
//        float2(0.0, 0),
        float2(0.4, 0.1),
//        float2(0.45, 0.45),
//        float2(0, 0),
        float2(0.5, 0.5),
        float2(0.75, 0.55),
//        float2(0.05, 0.85),
        float2(0.8, 0.9),
    float2(1, 1),
  };
//  float4 continental = x5t(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
  float4 continental = x5(continentalness);
//  float4 continental = linear(continentalness);
//  float2 erosionShape[] = {
//    float2(-1, 1),
//    float2(-0.7, 0.5),
//    float2(-0.3, 0),
//    float2(-0.25, 0.15),
//    float2(0, -0.8),
//    float2(0, 0.8),
//    float2(0.05, 0.85),
//    float2(0.5, 0.9),
//    float2(1, 1),
//  };
//  float4 erosion = x5t(erosionness, erosionShape, sizeof(erosionShape)/sizeof(float2));
//  float4 peaks = linear(peaksness);
  return
  continental * amplitude
//  + erosionness * 10000
//  + peaksness * 5000
  ;
}

float4 calculateDetail(int3 cubeOrigin, int cubeSize, float2 p, float octaves) {
  float3 cubeOffset = float3(p.x, 0, p.y);
  return fbmInf3(cubeOrigin, cubeSize, cubeOffset, 1, 0.1, octaves, 0, 0);
}
