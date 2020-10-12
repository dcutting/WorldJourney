#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
using namespace metal;

bool is_on_screen(float2 p) {
  return (p.x > -1 && p.x < 1) && (p.y > -1 && p.y < 1);
}

kernel void tessellation_kernel(constant float *edge_factors [[buffer(0)]],
                                constant float *inside_factors [[buffer(1)]],
                                device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float3 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant Terrain &terrain [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]) {
  
  float totalTessellation = 0;
  float minTessellation = 1;

  bool hasTessellation = false;

  uint index = pid * 4;
  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;
    
    float3 a = control_points[pointAIndex + index];
    float3 b = control_points[pointBIndex + index];
    
    
    TerrainSample sampleA = sample_terrain_michelic(a,
                                                    terrain.sphereRadius,
                                                    terrain.sphereRadius + terrain.fractal.amplitude,
                                                    length_squared(uniforms.cameraPosition),
                                                    uniforms.cameraPosition,
                                                    uniforms.modelMatrix,
                                                    terrain.fractal);
    float3 worldPositionA = sampleA.position;
    
    float4 clipPositionA = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPositionA, 1);

    
    
    TerrainSample sampleB = sample_terrain_michelic(b,
                                                    terrain.sphereRadius,
                                                    terrain.sphereRadius + terrain.fractal.amplitude,
                                                    length_squared(uniforms.cameraPosition),
                                                    uniforms.cameraPosition,
                                                    uniforms.modelMatrix,
                                                    terrain.fractal);
    float3 worldPositionB = sampleB.position;
    
    float4 clipPositionB = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPositionB, 1);
    
    float tessellation = 0;
    
    float2 sA = clipPositionA.xy / clipPositionA.w;
    float2 sB = clipPositionB.xy / clipPositionB.w;
    
    if (is_on_screen(sA) || is_on_screen(sB)) {
      hasTessellation = true;
    }
    
    if (is_on_screen(sA) && is_on_screen(sB))
    {
      sA.x = (sA.x + 1.0) / 2.0 * uniforms.screenWidth;
      sA.y = (sA.y + 1.0) / 2.0 * uniforms.screenHeight;
      sB.x = (sB.x + 1.0) / 2.0 * uniforms.screenWidth;
      sB.y = (sB.y + 1.0) / 2.0 * uniforms.screenHeight;
      float screenLength = distance(sA, sB);

      
      tessellation = ceil(screenLength / TESSELLATION_SIDELENGTH);
      tessellation = clamp(tessellation, (float)minTessellation, (float)terrain.tessellation);
    }
    
    
    
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  
  if (hasTessellation) {
    for (int i = 0; i < 4; i++) {
      int pointAIndex = i;
      int pointBIndex = i + 1;
      if (pointAIndex == 3) {
        pointBIndex = 0;
      }
      int edgeIndex = pointBIndex;
      if (factors[pid].edgeTessellationFactor[edgeIndex] < minTessellation) {
        factors[pid].edgeTessellationFactor[edgeIndex] = minTessellation;
        totalTessellation += minTessellation;
      }
    }
  }
  
  factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}
