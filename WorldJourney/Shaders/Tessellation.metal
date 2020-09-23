#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
using namespace metal;

constant int minTessellation = 1;



/** tessellation kernel */

kernel void eden_tessellation(constant float *edge_factors [[buffer(0)]],
                              constant float *inside_factors [[buffer(1)]],
                              device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                              constant float3 *control_points [[buffer(3)]],
                              constant Uniforms &uniforms [[buffer(4)]],
                              constant Terrain &terrain [[buffer(5)]],
                              texture2d<float> heightMap [[texture(0)]],
                              texture2d<float> noiseMap [[texture(1)]],
                              uint pid [[thread_position_in_grid]]) {
  
  uint index = pid * 4;
  float totalTessellation = 0;
  bool hasTessellated = false;
  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;
    
    float3 pA = (uniforms.modelMatrix * float4(control_points[pointAIndex + index], 1)).xyz;
    float aH = get_height(sample_terrain(pA, terrain.fractal));
    float3 pointA = float3(pA.x, aH, pA.y);
    
    float3 pB = (uniforms.modelMatrix * float4(control_points[pointBIndex + index], 1)).xyz;
    float bH = get_height(sample_terrain(pB, terrain.fractal));
    float3 pointB = float3(pB.x, bH, pB.y);
    
    //    float3 camera = uniforms.cameraPosition;
    //
    //    float d = calc_distance(pointA,
    //                            pointB,
    //                            camera);
    //    float numer = 256 * uniforms.scale;
    //    float denom = (d);// / (uniforms.scale * uniforms.scale));
    //    float stepped = (numer)/(denom);
    ////    float stepped = exp(-0.000001*pow(d, 1.95));
    ////    float stepped = pow( 4.0*d*(1.0-d), 10 );
    ////    float stepped = 2-exp(d/1);
    //    float tessellation = minTessellation + saturate(stepped) * (terrain.tessellation - minTessellation);
    
    float2 camera = uniforms.cameraPosition.xz;
    
    // TODO
    float3 sA = pointA;//sphericalise(terrain.sphereRadius, pointA, camera);
    float3 sB = pointB;//sphericalise(terrain.sphereRadius, pointB, camera);
    
    float4x4 vpMatrix = uniforms.projectionMatrix * uniforms.viewMatrix;
    
    float4 projectedA = vpMatrix * float4(sA, 1);
    float4 projectedB = vpMatrix * float4(sB, 1);
    
    float tessellation = hasTessellated ? 1 : 0; // discard by default.
    
    float near = 1.0;
    
    float4 v1 = projectedA;
    float4 v2 = projectedB;
    
    float w1 = v1.w;
    float w2 = v2.w;
    
    float4 first;
    float4 second;
    float n = 1;
    
    bool isVisible = true;
    
    // TODO: this really doesn't work properly.
    
    //    if (w1 >= near && w2 >= near) {
    // both in front of camera
    first = v1;
    second = v2;
    //    } else if (w1 >= near && w2 < near) {
    //      // only v1 in front
    //      first = v1;
    //      second = intersectionWithNearPlane(v1, v2, near);
    //      n = (v1.w - near) / (v1.w - v2.w);
    //    } else if (w1 < near && w2 >= near) {
    //      // only v2 in front
    //      first = v2;
    //      second = intersectionWithNearPlane(v2, v1, near);
    //      n = (v2.w - near) / (v2.w - v1.w);
    //    } else {
    //      // both behind
    //      isVisible = false;
    //    }
    //
    //    if (isVisible) {
    //      hasTessellated = true;
    
    float2 screenA = first.xy / first.w;
    float2 screenB = second.xy / second.w;
    
    //    if ((screenA.x > -1 && screenA.x < 1) && (screenA.y > -1 && screenA.y < 1) && (screenB.x > -1 && screenB.x < 1) && (screenB.y > -1 && screenB.y < 1))
    {
      screenA.x = (screenA.x + 1.0) / 2.0 * uniforms.screenWidth;
      screenA.y = (screenA.y + 1.0) / 2.0 * uniforms.screenHeight;
      screenB.x = (screenB.x + 1.0) / 2.0 * uniforms.screenWidth;
      screenB.y = (screenB.y + 1.0) / 2.0 * uniforms.screenHeight;
      
      // TODO: screenLength is definitely not right in some cases, maybe when some of the points of the quad are behind the camera?
      float screenLength = distance(screenA, screenB);
      
      // scale by amount of line that's in front of near clip plane (n).
      tessellation = n * (screenLength / TESSELLATION_SIDELENGTH);
      tessellation = clamp(tessellation, (float)minTessellation, (float)terrain.tessellation);
    }
    
    if (NO_TESSELLATION) {
      tessellation = minTessellation;
    }
    
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}
