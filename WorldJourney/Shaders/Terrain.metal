#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "Terrain.h"
#include "../Noise/ProceduralNoise.h"

float3 sphericalise_flat_gradient(float3 gradient, float amplitude, float3 unitSurfacePoint) {
  // https://math.stackexchange.com/questions/1071662/surface-normal-to-point-on-displaced-sphere
  float scaled_amplitude = amplitude / 2.0;
  float3 h = gradient - (dot(gradient, unitSurfacePoint) * unitSurfacePoint);
  float3 n = unitSurfacePoint - (scaled_amplitude * h);
  return normalize(n);
}

float4 scale_terrain_sample(float4 sample, float amplitude) {
  float4 scaled = sample / 2.0;
  float4 translated(scaled.x + amplitude / 2.0, scaled.yzw);
  return translated;
}

// TODO: Note that it might be possible for FBM terrain to be above/below amplitude since it's layering multiple octaves.
float4 sample_terrain(float3 p, Fractal fractal) {
  float4 sample;

//  sample = fractal.amplitude * simplex_noised_3d(p * fractal.frequency);

  if (fractal.warp > 0) {
    float4 warp = simplex_noised_3d(p / 100);
    sample = fbm_simplex_noised_3d(p*fractal.frequency + fractal.warp * warp.xxx, fractal);
  } else {
    sample = fbm_simplex_noised_3d(p*fractal.frequency, fractal);
  }
  
  return scale_terrain_sample(sample, fractal.amplitude);
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
