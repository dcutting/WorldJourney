#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
using namespace metal;

kernel void tessellation_kernel(constant float *edge_factors [[buffer(0)]],
                                constant float *inside_factors [[buffer(1)]],
                                device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float3 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant Terrain &terrain [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]) {
  
  float totalTessellation = 0;

  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;
    
    float tessellation = 64;
    
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}
