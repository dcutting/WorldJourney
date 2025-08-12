#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/WorldTerrain.h"
#include "../Shared/Terrain.h"
#include "../Shared/Noise.h"
#include "../Shared/GridPosition.h"
#include "ShaderTypes.h"

float4 quintic(float4 g) {
  float f = g.x;
  float u = f*f*f*(f*(f*6.0-15.0)+10.0);
  float3 d = 30.0*f*f*(f*(f-2.0)+1.0) * g.yzw;
  return float4(u, d);
}

float4 sculpt(float4 g, float2 shape[], int shapeCount) {
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
  float4 sg = quintic(float4(sx, g.yzw / (q.x - p.x)));
  sg.x = sg.x * (q.y - p.y) + p.y;
  sg.yzw *= (q.y - p.y);
  return sg;
}

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 x) {
  float2 continentalShape[] = {
        float2(-0.89, -4000),
        float2(-0.2, -3000),
        float2(0, -200),
        float2(0.0, 0),
        float2(0.01, 200),
        float2(0.3, 840)
  };
  float2 plateauShape[] = {
        float2(0.0, 0),
        float2(0.1, 0.1),
        float2(0.3, 1)
  };
  float2 craterShape[] = {
        float2(0.0, 1),
        float2(0.2, 0)
  };
  float2 erosionShape[] = {
    float2(0, 0),
    float2(0.05, 0.1),
    float2(0.5, 0.3),
    float2(0.7, 0.4),
    float2(1, 1),
  };
  float2 mountainShape[] = {
        float2(0.0, 0),
        float2(0.01, 0.5),
        float2(0.014, 0),
        float2(0.86, 0),
        float2(0.9, 0.2),
        float2(0.91, 0)
  };

  float3 cubeOffset = float3(x.x, 0, x.y);
  GridPosition p = makeGridPosition(cubeOrigin, cubeSize, cubeOffset);

  float4 continentalness = fbmRegular(p, 0.0000007, 4) + fbmSquared(p, 0.00003, 6) * 0.1;
  float4 continentalness2 = eroded(p, 0.0000004, 4) + eroded(p, 0.000021, 6) * 0.2;
//  float4 continentalness3 = fbmRegular(p, 0.000009, 20);
//  float4 detail = fbmRegular(p, 1, 8);
//  float4 hills = jordanTurbulence(p, 0.0001, 5);

  float4 continental = sculpt(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
  float4 continental2 = sculpt(continentalness2, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float4 continental3 = sculpt(continentalness3, continentalShape, sizeof(continentalShape)/sizeof(float2));

  float cs = smoothstep(100, -100, continental.x);
  float4 plateauness = fbmRegular(p, 0.001, cs * 16);
  float4 plateau = sculpt(plateauness, plateauShape, sizeof(plateauShape)/sizeof(float2));
//  float4 mountainous = sculpt(continentalness, mountainShape, sizeof(mountainShape)/sizeof(float2));

  float4 peaksness = swissTurbulence(p, 0.0001, (1 - cs) * 16);

  return
  + continental
  + continental2 * 1
//  + continental3 * 0.1
//  + detail * 0.01
//  + hills * 400
  + plateau * 20
//  + mountainous * 1000
  + peaksness * 1000
  ;
}
