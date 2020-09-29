#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "Terrain.h"
#include "../Noise/ProceduralNoise.h"

float4 sample_terrain(float3 p, Fractal fractal) {
  return fbm_simplex_noised_3d(p, fractal);
//  return fractal_simplex_noised_3d(p, fractal.frequency, fractal.amplitude);
}

float3 find_unit_spherical_for_template(float3 p, float r, float R, float d_sq, float3 eye) {
  float r_sq = powr(r, 2);
  float R_sq = powr(R, 2);
  float h = sqrt(d_sq - r_sq);
  float s = sqrt(R_sq - r_sq);
  
  float zs = (R_sq + d_sq - powr(h+s, 2)) / (2 * r * (h+s));
  
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

TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, float4x4 modelMatrix, Fractal fractal) {
  float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d_sq, eye);
  float4 modelled = float4(unit_spherical * r, 1) * modelMatrix;
  float4 noised = sample_terrain(modelled.xyz, fractal);
  
  float height = noised.x;
  float altitude = r + height;
  float3 position = altitude * unit_spherical;
  float3 scaled_gradient = noised.yzw / altitude;
  return {
    .height = height,
    .position = position,
    .gradient = scaled_gradient
  };
}
