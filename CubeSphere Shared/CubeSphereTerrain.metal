#include "../Shared/InfiniteNoise.h"
#include "../Shared/GridPosition.h"
#include "../Shared/Sculpt.h"

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 x) {
  GridPosition p = makeGridPosition(cubeOrigin, cubeSize, float3(x.x, 0, x.y));

//  float4 continentalness = fbmRegular(p, 0.0000005, 4);
//  float4 continental = sculpt(continentalness, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float4 continentalness2 = fbmWarped(p, 0.000004, 12, 0.0000005, 3, 600000);
//  float4 continental2 = sculpt(continentalness2, continentalShape, sizeof(continentalShape)/sizeof(float2));
//  float4 continentalness3 = fbmRegular(p, 0.00002, 12);
//  float4 continental3 = sculpt(continentalness3, plateauShape, sizeof(plateauShape)/sizeof(float2));
//  float cs = smoothstep(0, 100, continental.x);
//  float c2s = saturate(continentalness2.x * cs);
//  float4 hills2 = fbmEroded(p, 0.001, 18 * cs) * cs;
//  float4 hills = sculpt(hills2, plateauShape, sizeof(plateauShape)/sizeof(float2));
//  float bumps = 1.0 - smoothstep(-1.0, 0.3, hills.x);
//  float4 hills = fbmWarped(p, 0.0002, 18, 0.001, 3, 14);
//  float4 hills = fbmCubed(p, 0.0002, 4);
  float4 basic = fbmCubed(p, 0.003, 28);

  return
//  0
//  + continentalness * 4000
//  + continental
//  + continental2 * 0.4
//  + continental3 * 0.1
//  + hills * 300
  + basic * 100
  ;
}
