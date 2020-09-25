#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "Terrain.h"
#include "../Noise/ProceduralNoise.h"

//NormalFrame normal_frame(float3 normal) {
//  return {
//    .normal = normal,
//    .tangent = float3(1, 0, 0), // TODO: fix this.
//    .bitangent = float3(0, 0, 1)
//  };
//}

float4 sample_terrain(float3 p) {
  return fbm_simplex_noised_3d(p / 20000000, 5) * 3000;  // TODO: should use Fractal configuration.
//  return simplex_noised_3d(p/1000) * 1000;
}

float3 find_unit_spherical_for_template(float3 p, float r, float R, float d, float3 eye) {
  float h = sqrt(powr(d, 2) - powr(r, 2));
  float s = sqrt(powr(R, 2) - powr(r, 2));
  
  float zs = (powr(R, 2) + powr(d, 2) - powr(h+s, 2)) / (2 * r * (h+s));
  
  float3 z = float3(0.0, 0.0, zs);
  float3 g = p;
  float n = 4;
  g.z = (1 - powr(g.x, n)) * (1 - powr(g.y, n));
  float3 gp = g + z;
  float mgp = length(gp);
  float3 vector = gp / mgp;
  
  float3 b = float3(0, 0.1002310, 0.937189); // Note: this has to be linearly independent of eye.
  float3 w = eye / length(eye);
  float3 wb = cross(w, b);
  float3 v = wb / length(wb);
  float3 u = cross(w, v);
  float3x3 rotation = transpose(float3x3(u, v, w));
  
  float3 rotated = vector * rotation;
  return rotated;
}

TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d, float f, float a, float3 eye, float4x4 modelMatrix) {
  float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d, eye);
  float4 modelled = float4(unit_spherical * r, 1) * modelMatrix;
  float4 noised = sample_terrain(modelled.xyz);
  float altitude = r + noised.x;
  float3 v = unit_spherical * altitude;
  return {
    .position = v,
    .normal = noised.yzw
  };
}
