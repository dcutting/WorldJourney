#include <metal_stdlib>
#include <simd/simd.h>
#include "Terrain.h"
#include "Noise.h"

float4 scale_terrain_sample(float4 sample, float amplitude) {
//  float hamp = amplitude / 2.0;
//  float4 scaled = sample / 2.0;
//  float4 translated(scaled.x + hamp, scaled.yzw);
  float4 translated = sample;
  return translated;
}

// TODO: Note that it might be possible for FBM terrain to be above/below amplitude since it's layering multiple octaves.
float4 sample_terrain(float3 pp, Terrain terrain, Fractal fractal) {
  bool warp = false;
  float f = fractal.frequency;
  float a = fractal.amplitude;
  float l = fractal.lacunarity;
  float p = fractal.persistence;
  int o = fractal.octaves;
  if (warp) {
    float3 q = float3(fbmd_7(p + float3(2, 3, 2), f, a, l, p, o).x,
                      fbmd_7(p + float3(6, -1, -6), f, a, l, p, o).x,
                      fbmd_7(p + float3(-1, 3, 5), f, a, l, p, o).x);
    pp = pp + 1 * q;
  }
  float4 sample = fbmd_7(pp, f, a, l, p, o);
//  sample.x = sample.x / 2 + 0.5;
  float h = sample.x;
  float ph = pow(abs(h), 2);
  float r = h * ph * 1000.0;
  sample.x = r;
//  float4 adjusted = sample;
//  float4 billow = abs(sample);
//  float4 ridge = float4(1-billow.x, sample.y, sample.z, sample.w);
////  adjusted.yzw *= fractal.warpAmplitude;
  float4 adjusted = sample;
  return scale_terrain_sample(adjusted, terrain.fractal.amplitude);
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

TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, Terrain terrain, Fractal fractal) {
  float3 unit_spherical = float3(p);// find_unit_spherical_for_template(p, r, R, d_sq, eye);
  return sample_terrain_spherical(unit_spherical, r, terrain, fractal);
}

TerrainSample sample_terrain_spherical(float3 unit_spherical, float r, Terrain terrain, Fractal fractal) {
  float4 modelled = float4(unit_spherical * r, 1);

  float4 noised = sample_terrain(modelled.xyz, terrain, fractal);
  
  float height = noised.x;
  float depth = terrain.waterLevel - height;
  float3 scaled_gradient = noised.yzw;// / height;
//  float altitude = r + height;
  float3 gp = unit_spherical * r;
  float3 position = float3(gp.x, gp.y, gp.z-height);
  return {
    .depth = depth,
    .height = height,
    .position = position,
    .gradient = scaled_gradient
  };
}

TerrainSample sample_ocean_michelic(float3 p, float r, float R, float d_sq, float3 eye, Terrain terrain, Fractal fractal, float time) {
  float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d_sq, eye);
  Gerstner g = gerstner(unit_spherical, terrain.sphereRadius + terrain.waterLevel, time);
  return {
    .depth = 1,
    .height = 1,
    .position = g.position,
    .gradient = g.normal
  };
}

//float adaptiveOctaves(float dist, int maxOctaves, float minDist, float maxDist) {
//  int minOctaves = 0;
//  float factor = smoothstep(minDist, maxDist, dist);
//  
//  float i = dist;
//  float A = maxDist;
//  float B = minDist;
//  float N = A - B;
//  float v2 = i / N;
//  v2 = pow(v2, 0.05);
//
//  factor = saturate(v2);
//
//  float detailFactor = 1.0 - (factor * 0.99 + 0.001);
//
//  float fractOctaves = (maxOctaves - minOctaves) * detailFactor + minOctaves;
//  
//  return fractOctaves;
//}

//float worldDiffForScreenSpace(constant Uniforms &uniforms, float4 wp, int pixels) {
//  float min = 0;
//  float max = 10;
//  float candidate = 5;
//  for (int i = 0; i < 100; i++) {
//    float4 wp2 = float4(wp.xyz / wp.w + float3(0, candidate, 0), 1);
//    float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * wp;
//    float4 p2 = uniforms.projectionMatrix * uniforms.viewMatrix * wp2;
//    float nDiff = abs(p2.y/p2.w - p.y/p.w);
//    int ssDiff = int(nDiff * uniforms.screenHeight);
//    if (ssDiff == pixels) {
//      break;
//    }
//    if (ssDiff > pixels) {
//      max = candidate;
//      candidate = (candidate - min) / 2.0 + min;
//    } else {
//      min = candidate;
//      candidate = (max - candidate) / 2.0 + candidate;
//    }
//  }
//  return candidate;
//}

float3 applyFog(float3  rgb,      // original color of the pixel
                float distance,   // camera to point distance
                float3  rayDir,   // camera to point vector
                float3  sunDir )  // sun light direction
{
  float b = 0.001;
  float fogAmount = 1.0 - exp( -distance*b );
  float sunAmount = max( dot( rayDir, sunDir ), 0.0 );
  float3  fogColor  = mix( float3(0.7,0.4,0.3), //float3(0.5,0.6,0.7), // bluish
                          float3(1.0,0.6,0.2), //float3(1.0,0.9,0.7), // yellowish
                          pow(sunAmount,8.0) );
  return mix( rgb, fogColor, fogAmount );
}

float3 gammaCorrect(float3 colour) {
  return pow(colour, float3(1.0/2.2));
}