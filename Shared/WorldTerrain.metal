#include <metal_stdlib>
#include "InfiniteNoise.h"
#include "../Shared/Noise.h"

using namespace metal;

float4 sampleInf(int3 cubeOrigin, int cubeSize, float3 x, float a, float o, float t) {
//  float ff = 1;
//  float qd = 100;//t*100;
//  int qo = 2;
//  float qf = 0.00001;
//  float sd = 10;
//  int so = 10;
//  float sf = 0.000005;
//  float3 o1 = ff*float3(-3.2, 9.2, -8.3)/(float)cubeSize;
//  float3 o2 = ff*float3(1.1, -3, 4.7)/(float)cubeSize;
////  float3 o3 = float3(2.8, 0, -2.1)/(float)cubeSize;
//  float4 qx = fbmInf3(cubeOrigin, cubeSize, x+qd*o1, qf, 1, qo, 0);
//  float4 qy = fbmInf3(cubeOrigin, cubeSize, x+qd*o2, qf, 1, qo, 0);
//  float3 q = float3(qx.x, 0, qy.x) / (float)cubeSize;
//  float4 s = fbmInf3(cubeOrigin, cubeSize, x + sd*q, sf, 10, so, 0);
//  float ap = a * s.x;
//  float4 sharpnessN = fbmInf3(cubeOrigin, cubeSize, x, 0.0000005, 1, 3, 0);
  float sharpness = 1;//clamp(sharpnessN.x, -1.0, 1.0);
  float4 terrain = fbmInf3(cubeOrigin, cubeSize, x, 0.00005, a, o, sharpness);
  return terrain;
}

// Returns a value between -1 and 1.
float2 warp(float2 p, float f, float2 dx, float2 dy) {
  int o = 3;

  float3 qx = fbm2(p+dx, f, 1, 2, 0.5, o, 1, 0, 0);
  float3 qy = fbm2(p+dy, f, 1, 2, 0.5, o, 1, 0, 0);
  float2 q = float2(qx.x, qy.x);
  return q / 2.0;
}