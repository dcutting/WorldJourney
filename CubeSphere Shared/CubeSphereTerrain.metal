#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/WorldTerrain.h"
#include "../Shared/Terrain.h"
#include "../Shared/Noise.h"
#include "../Shared/GridPosition.h"
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

  float sx = (g.x - p.x) / (q.x - p.x);
  float4 sg = x5(float4(sx, g.yzw / (q.x - p.x)));
  sg.x = sg.x * (q.y - p.y) + p.y;
  sg.yzw *= (q.y - p.y);
  return sg;
}

float4 normalizeTerrain(float4 in) {
  return float4(in.x * 0.5 + 0.5, in.y, in.z, in.w);
}

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 x, float amplitude, float octaves, float epsilon) {
  float3 cubeOffset = float3(x.x, 0, x.y);
  GridPosition p = makeGridPosition(cubeOrigin, cubeSize, cubeOffset);
//  float4 detailModulator = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.01, 1, 12, 0, 0);
//  float4 detailModulator2 = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.000012, 1, 6, 0, 0);
//  float4 continentalness = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.0000005, 1, 12, 0, 0);
//  float4 continentalness = fbmRegular(p, 0.0000005, 2) - 1;
  float4 continentalness = fbmRegular(p, 0.0000005, 12);
//  float4 plateauness = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.001, 1, 20, 0, 0);
  float4 plateauness = fbmRegular(p, 0.00001, 12);
//  float4 plateauness = jordanTurbulence(p, 0.001, 24);
//  float4 plateauness = eroded(p, 0.0003, 14);
//  float4 plateauness = swissTurbulence(p, 0.0003, 14);
//  float4 mountainMask = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.000005, 1, 5, 0, 0);
//  float4 plateauMask = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.0000001, 1, 12, 0, 0);
////  float4 erosionMask = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.00002, 1, 10, 0, 0);
//  float4 peaksness = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.00005, 1, 16, detailModulator2.x, 0);
//  float4 hills = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.0001, 1, 5, 0, 0);
  float4 hills =
//  + jordanTurbulence(p, 0.5, 12) * 0.0005
//    + jordanTurbulence(p, 0.001, 12)
//    + eroded(p, 0.0001, 12)
//    + fbmCubed(p, 0.002, 18) * 0.5
    + swissTurbulence(p, 0.002, 18) * 0.1
    ;

//  float4 detail = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.02, detailModulator.x * detailModulator.x, 12, clamp(detailModulator.y*detailModulator.z, -1.0, 1.0), 0);
//  float4 detail = jordanTurbulence(p, 0.001, 12);
//  float4 detail = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.02, 1, 12, -1.0, 1.0);
//  float4 fineDetail = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 2, 1, 8, 0, 0);
//  float4 fineDetail = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 1, 0.1, 12, 0, 0);

//  float4 warpX = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.00001, 1, 4, 0, 0);
//  float4 warpY = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.00001, 1, 4, 0, 0);
//  float3 warpedCubeOffset = cubeOffset + float3(warpX.x, 0, warpY.x);
//  float4 peaksness = fbmInf3(cubeOrigin + int3(floor(warpedCubeOffset)), cubeSize, fract(warpedCubeOffset), 0.000001, 1, 20, 0.5, 0);

  float2 continentalShape[] = {
//        float2(-0.9, 2),
        float2(-0.89, -4000),
        float2(-0.2, -3000),
        float2(0, -200),
        float2(0.0, 0),
        float2(0.01, 200),
        float2(0.3, 840)
  };
  float4 continental = x5t(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
  float2 plateauShape[] = {
        float2(0.0, 0),
        float2(0.1, 0.1),
        float2(0.3, 1)
  };
  float4 plateau = x5t(plateauness, plateauShape, sizeof(plateauShape)/sizeof(float2));
//  float4 fine = x5t(fineDetail, continentalShape, sizeof(continentalShape)/sizeof(float2));

  float2 erosionShape[] = {
    float2(0, 0),
    float2(0.05, 0.1),
    float2(0.5, 0.3),
    float2(0.7, 0.4),
    float2(1, 1),
  };
//  float4 erosion = x5t(continentalness, erosionShape, sizeof(erosionShape)/sizeof(float2));

  float2 mountainShape[] = {
        float2(0.0, 0),
        float2(0.01, 0.5),
        float2(0.014, 0),
        float2(0.86, 0),
        float2(0.9, 0.2),
        float2(0.91, 0)
  };
//  float4 mountainous = x5t(continentalness, mountainShape, sizeof(mountainShape)/sizeof(float2));

  return
  + continental
//  + plateau * 200 * plateauMask.x// * erosion.x// saturate(continental)
  + plateau * 300
//  + erosion * 1000 * saturate(erosionMask.x)
  + hills * 100// * -erosion.x
//  + peaksness * 3000 * -erosion.x * saturate(mountainMask.x * mountainMask.x) * saturate(continentalness.x)
//  + saturate(peaksness) * 1000
//  + normalizeTerrain(peaksness) * 3000 * saturate(mountainous.x) * saturate(mountainMask.x)
//  + detail * 100
//  + fine * 0.000001
  ;
}

//float4 calculateDetail(int3 cubeOrigin, int cubeSize, float2 p, float octaves) {
//  float3 cubeOffset = float3(p.x, 0, p.y);
//  return fbmInf3(cubeOrigin, cubeSize, cubeOffset, 1, 0.1, octaves, 0, 0);
//}
