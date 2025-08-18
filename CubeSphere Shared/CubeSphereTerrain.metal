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

float4 sculpt(float4 g, constant float2 shape[], int shapeCount) {
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

constant float2 continentalShape[] = {
      float2(-0.89, -4000),
      float2(-0.2, -3000),
      float2(0, -200),
      float2(0.0, 0),
      float2(0.01, 200),
      float2(0.3, 840)
};

constant float2 plateauShape[] = {
      float2(0.0, 0),
      float2(0.1, 0.1),
      float2(0.3, 1)
};

constant float2 craterShape[] = {
      float2(0.0, 1),
      float2(0.2, 0)
};

constant float2 erosionShape[] = {
  float2(0, 0),
  float2(0.05, 0.1),
  float2(0.5, 0.3),
  float2(0.7, 0.4),
  float2(1, 1),
};

constant float2 mountainShape[] = {
      float2(0.0, 0),
      float2(0.01, 0.5),
      float2(0.014, 0),
      float2(0.86, 0),
      float2(0.9, 0.2),
      float2(0.91, 0)
};

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 x) {
  float3 cubeOffset = float3(x.x, 0, x.y);
  GridPosition p = makeGridPosition(cubeOrigin, cubeSize, cubeOffset);

  float4 continentalness = fbmRegular(p, 0.000001, 8);
//  float4 continentalness2 = fbmEroded(p, 0.0000004, 4) + fbmEroded(p, 0.000021, 6) * 0.2;
//  float4 continentalness3 = fbmRegular(p, 0.0009, 10);
//
  float4 continental = sculpt(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float4 continental2 = sculpt(continentalness2, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float4 continental3 = sculpt(continentalness3, continentalShape, sizeof(continentalShape)/sizeof(float2));

  float cs = smoothstep(0, 500, continental.x);
//  float mcs = 1;// - cs;

  float4 patch1 = fbmRegular(p, 0.000005, 12);
  float4 patch2 = fbmRegular(p, 0.0001, 12);
  float4 mountainPlateau = sculpt(patch1, plateauShape, sizeof(plateauShape)/sizeof(float2));
  float4 bouldery = sculpt(patch2, plateauShape, sizeof(plateauShape)/sizeof(float2));
  float ms = smoothstep(0, 1, mountainPlateau.x) * cs;
  float bs = smoothstep(0, 1, bouldery.x);
  float mcs = 1 - ms;
  float mbs = 1 - bs;
  float4 mountains = swissTurbulence(p, 0.0001, ms * 18) * ms;
  float4 hills = fbmCubed(p, 0.001, bs * 18) * bs;
  float4 mounds = fbmEroded(p, 0.2, mcs * 8) * mcs;

  return
  + continental
//  + continental2 * 1
//  + continental3 * 0.01
//  + mountainness * 1000
//  + mountainPlateau * 100
  + mountains * 2000
  + hills * 300
  + mounds * 0.1
  ;
}
