#include "../Shared/InfiniteNoise.h"
#include "../Shared/GridPosition.h"
#include "../Shared/Sculpt.h"

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 x) {
//  GridPosition p = makeGridPosition(cubeOrigin, cubeSize, float3(x.x, 0, x.y));

//  float4 continentalness = fbmRegular(p, 0.0000005, 8);//, 0.0000005, 3, 600000);
//  float4 continental = sculpt(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float4 continentalness2 = fbmWarped(p, 0.000004, 16, 0.0000005, 4, 600000);
//  float4 continental2 = sculpt(continentalness2, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float cs = smoothstep(0, 100, continental.x);
//  float c2s = saturate(continentalness2.x * cs);
//  float4 hills = fbmRegular(p, 0.0001, 18);
//  float bumps = 1.0 - smoothstep(-1.0, 0.3, hills.x);
//  float4 hills = fbmWarped(p, 0.0001, 18, 0.001, 3, 14);
//  float bumps = 1.0;
//  float4 basic = fbmCubed(p, 0.3, bumps * 18) * bumps;

  return
  0
//  + continental
//  + continental2
//  + hills * 1000
//  + basic * 1
  ;
}
