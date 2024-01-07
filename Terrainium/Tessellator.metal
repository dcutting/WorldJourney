#include <metal_stdlib>
#include "Common.h"
#include "../PersistentGrid/Maths.h"
#include "../PersistentGrid/WorldTerrain.h"

using namespace metal;

//constant float f = 1;

//struct Sampled {
//  float2 xy;
//  float w;
//};

//bool is_off_screen_behind(Sampled s[]) {
//  for (int i = 0; i < 8; i++) {
//    if (s[i].w > 0) {
//      return false;
//    }
//  }
//  return true;
//}
//
//bool is_off_screen_left(Sampled s[]) {
//  for (int i = 0; i < 8; i++) {
//    if (s[i].xy.x >= -f) {
//      return false;
//    }
//  }
//  return true;
//}
//
//bool is_off_screen_right(Sampled s[]) {
//  for (int i = 0; i < 8; i++) {
//    if (s[i].xy.x <= f) {
//      return false;
//    }
//  }
//  return true;
//}
//
//bool is_off_screen_up(Sampled s[]) {
//  for (int i = 0; i < 8; i++) {
//    if (s[i].xy.y >= -f) {
//      return false;
//    }
//  }
//  return true;
//}
//
//bool is_off_screen_down(Sampled s[]) {
//  for (int i = 0; i < 8; i++) {
//    if (s[i].xy.y <= f) {
//      return false;
//    }
//  }
//  return true;
//}

kernel void tessellation_kernel(device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                                constant float2 *control_points [[buffer(3)]],
                                constant Uniforms &uniforms [[buffer(4)]],
                                constant QuadUniforms *quadUniforms [[buffer(5)]],
                                uint pid [[thread_position_in_grid]]
                                ) {
  
  float totalTessellation = 0;
//  uint control_point_index = pid * 4;
  
//  // frustum culling
//
//  Sampled corners[8];
//  for (int i = 0; i < 4; i++) {
//    float3 position = control_points[i+control_point_index];
//
//    float4 bottom = float4(position.x, 0, position.y, 1);
//    float4 top = float4(position.x, 2, position.y, 1);
//
//    // TODO: need a way of properly bounding the terrain height - it's not exactly sphere radius + amplitude.
//
//    float4 clipBottom = uniforms.projectionMatrix * uniforms.viewMatrix * bottom;
//    Sampled sampledBottom = {
//      .xy = (clipBottom.xy / clipBottom.w),// * (clipBottom.w > 0 ? 1 : -1),
//      .w = clipBottom.w
//    };
//
//    float4 clipTop = uniforms.projectionMatrix * uniforms.viewMatrix * top;
//    Sampled sampledTop = {
//      .xy = (clipTop.xy / clipTop.w),// * (clipTop.w > 0 ? 1 : -1),
//      .w = clipTop.w
//    };
//
//    corners[i*2] = sampledBottom;
//    corners[i*2+1] = sampledTop;
//  }
//
//  if (is_off_screen_behind(corners) ||
//      is_off_screen_left(corners) ||
//      is_off_screen_right(corners) ||
//      is_off_screen_up(corners) ||
//      is_off_screen_down(corners)) {
//    factors[pid].edgeTessellationFactor[0] = 0;
//    factors[pid].edgeTessellationFactor[1] = 0;
//    factors[pid].edgeTessellationFactor[2] = 0;
//    factors[pid].edgeTessellationFactor[3] = 0;
//    factors[pid].insideTessellationFactor[0] = 0;
//    factors[pid].insideTessellationFactor[1] = 0;
//    return;
//  }
  
  
  
  // sample corners
//
//  Sampled samples[4];
//  for (int i = 0; i < 4; i++) {
//    float2 position = control_points[i+control_point_index];
//
//    float4 v = float4(position.x, 0, position.y, 1.0);
//
//    float3 cubeInner = v.xyz;
//    float4 noise = sampleInf(quadUniforms[pid].cubeOrigin, quadUniforms[pid].cubeSize, cubeInner, uniforms.amplitudeLod, 2, uniforms.time);
//    float4 wp = quadUniforms[pid].modelMatrix * v;
//  //  float3 wp3 = normalize(wp.xyz);
//    float3 wp3 = wp.xyz;
//    float3 displaced = wp3 * (uniforms.radiusLod);// + (uniforms.amplitudeLod * noise.x));
//    displaced.y = uniforms.radiusLod + uniforms.amplitudeLod * noise.x;
//    float4 clip = uniforms.projectionMatrix * uniforms.viewMatrix * float4(displaced, 1);
//
////    float4 clip = uniforms.projectionMatrix * uniforms.viewMatrix * v;
//    Sampled sampled = {
//      .xy = (clip.xy / clip.w),
//      .w = clip.w
//    };
//    samples[i] = sampled;
//  }
//
  
  
  // tessellation calculations

  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;

    float minTessellation = 1;//MIN_TESSELLATION;
    float maxTessellation = 64;//MAX_TESSELLATION;
    float tessellation = minTessellation;

//    Sampled sA = samples[pointAIndex];
//    Sampled sB = samples[pointBIndex];
//
//    // Screenspace tessellation.
//    float2 sAxy = sA.xy;
//    float2 sBxy = sB.xy;
//    sAxy.x = (sAxy.x + 1.0) / 2.0 * uniforms.screenWidth;
//    sAxy.y = (sAxy.y + 1.0) / 2.0 * uniforms.screenHeight;
//    sBxy.x = (sBxy.x + 1.0) / 2.0 * uniforms.screenWidth;
//    sBxy.y = (sBxy.y + 1.0) / 2.0 * uniforms.screenHeight;
//    float screenLength = distance(sAxy, sBxy);
//    float screenTessellation = ceil(screenLength / 2.0);//USE_SCREEN_TESSELLATION_SIDELENGTH;

//    screenTessellation = 64;

//    // Gradient tessellation.
//    float3 n1 = sA.terrain.gradient;
//    float3 n2 = sB.terrain.gradient;
//    float t = (dot(normalize(n1), normalize(n2))); // TODO: can we also use the second derivative?
//    t = 1 - ((t + 1.0) / 2.0);
//    t = pow(t, 0.75);
//    float gradientTessellation = ceil(t * (MAX_TESSELLATION - MIN_TESSELLATION) + MIN_TESSELLATION);

    // Distance tessellation.
//    float d_pos1 = distance(sA.xy, float2(TERRAIN_PATCH_SIDE/2, TERRAIN_PATCH_SIDE/2));
//    float d_pos2 = distance(sB.xy, float2(TERRAIN_PATCH_SIDE/2, TERRAIN_PATCH_SIDE/2));
//    float d_pos = (d_pos1 + d_pos2) / 2.0;
//    d_pos /= (float)TERRAIN_PATCH_SIDE;
//    d_pos = 1 - d_pos;
//    d_pos = pow(d_pos, 2);
//    tessellation *= d_pos;
    
//    minTessellation = screenTessellation;
//    tessellation = screenTessellation;
    tessellation = quadUniforms[pid].tessellation[i];

    // clamp
    tessellation = clamp(tessellation, minTessellation, maxTessellation);
//    int tessellation = 16;
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  
  factors[pid].insideTessellationFactor[0] = (factors[pid].edgeTessellationFactor[1] + factors[pid].edgeTessellationFactor[3]) / 2;
  factors[pid].insideTessellationFactor[1] = (factors[pid].edgeTessellationFactor[0] + factors[pid].edgeTessellationFactor[2]) / 2;
}
