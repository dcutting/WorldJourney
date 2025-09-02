#include "../Shared/InfiniteNoise.h"
#include "../Shared/GridPosition.h"

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
  GridPosition p = makeGridPosition(cubeOrigin, cubeSize, float3(x.x, 0, x.y));

//  float4 continentalness = fbmWarped(p, 0.0000005, 28, 0.0000005, 6, 600000);
//  float4 continentalness = fbmRegular(p, 0.000001, 28);
//  float4 continentalness2 = fbmRegular(p, 0.00006, 6);
//  float4 continental = sculpt(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float cs = smoothstep(0, 100, continental.x);
//  float c2s = saturate(continentalness2.x * cs);
//  float4 hills = fbmWarped(p, 0.0001, c2s * 10 + 8, 0.001, 3, 20) * c2s;
  float4 basic = fbmCubed(p, 0.0003, 12);

  return
  basic * 1000
//  + continental
//  + hills * 3000
  ;
}
