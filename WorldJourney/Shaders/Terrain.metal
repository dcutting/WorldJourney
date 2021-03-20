#include <metal_stdlib>
#include <simd/simd.h>
#include "../Common.h"
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

  if (fractal.warpFrequency > 0) {
    float4 warp = simplex_noised_3d(p * fractal.warpFrequency);
    sample = fbm_simplex_noised_3d(p*fractal.frequency + fractal.warpAmplitude * warp.xxx, fractal);
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

float normalised_poleness(float y, float r) {
  return 1 - abs(y / r);
}

float2 cavity(float x) {
  float a = 0.02;
  float b = -20;
  float xp = x;
  float h = a * (xp * xp) + b;
  return float2(h, h * -2 * a * xp);
}

float4 cavity(float3 p) {
  float a = 0.02;
  float b = -20;
  float xp = p.x;
  float yp = p.y;
  float zp = p.z;
  float h = a * (xp * xp) + a * (yp * yp) + a * (zp * zp) + b;
  return float4(h, h * -2 * a * xp, h * -2 * a * yp, h * -2 * a * zp);
}

float rim(float x, float rimWidth) {
  float rimSteepness = 0.01;
  float xp = abs(x) - 1 - rimWidth;
  float h = rimSteepness * xp * xp;
  return h;
}

float4 rim(float3 p, float height, float compactness) {
  float a = height;
  float b = 0;
  float c = compactness;
  // Gaussian
  float h = a * exp(-(p.x-b)*(p.x-b)/2*c*c) * exp(-(p.y-b)*(p.y-b)/2*c*c) * exp(-(p.z-b)*(p.z-b)/2*c*c);
  return float4(h, 0, 0, 0);
}

float floorshape(float x) {
  float floorHeight = 0;
  return floorHeight;
}

float4 floorshape(float3 p) {
  float floorHeight = 0;
  return float4(floorHeight, 0, 0, 0);
}

float smin(float a, float b, float k) {
  float h = clamp((b-a+k)/(2*k), 0.0, 1.0);
  return a * h + b * (1-h) - k * h * (1-h);
}

float sminCubic(float a, float b, float k) {
  float h = max( k-abs(a-b), 0.0 )/k;
  return min( a, b ) - h*h*h*k*(1.0/6.0);
}

float4 dMin(float4 a, float4 b) {
  if (a.x < b.x) {
    return a;
  } else {
    return b;
  }
}

float4 dMax(float4 a, float4 b) {
  if (a.x > b.x) {
    return a;
  } else {
    return b;
  }
}

float2 crater(float d, float width) {
  d /= 1;
  if (d > width) { return 0; }
  float2 cav = cavity(d);
  float ri = rim(d, width);
  float cavri = sminCubic(cav.x, ri, 10);
  float flr = floorshape(d);
  float cavriflr = max(cavri, flr);
  return float2(cavriflr, cav.y); // TODO: derivative not just of cavity...
}

float4 crater(float3 p, float3 c, float height, float compactness) {
  float4 ri = rim(c - p, height, compactness);
  if (ri.x < 0.1) { return 0; }
  float4 cav = cavity(c - p);
  float4 cavri = dMin(cav, ri);
  float4 flr = floorshape(c - p);
  float4 cavriflr = dMax(cavri, flr);
  return cavriflr;
}
  
//  float h = 0;
//  float3 dh = 0;
//  float d = distance(p, c);
//  d /= 1;
//  if (d > width) { return 0; }
//  float4 cav = cavity(c.x - p.x, c.y - p.y, c.z - p.z);
//  float4 ri = rim(c.x - p.x, c.y - p.y, c.z - p.z, width);
////  float cavri = sminCubic(cav.x, ri, 10);
//  if (ri.x < cav.x) {
//    h = ri.x;
//    dh = ri.yzw;
//  } else {
//    h = cav.x;
//    dh = cav.yzw;
//  }
//  float flr = floorshape(d);
//  if (flr > h) {
//    h = flr;
//    dh = 0;
////  } else {
////    h = cav.x;
////    dh = cav.yzw;
//  }
////  float cavriflr = max(cav.x, flr);
//  return float4(h, dh); // TODO: derivative not just of cavity...
//}

TerrainSample sample_terrain_michelic(float3 p, float r, float R, float d_sq, float3 eye, Fractal fractal) {
  float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d_sq, eye);

  float4 modelled = float4(unit_spherical * r, 1);

  Fractal warpedFractal = fractal;
//  float poleness = normalised_poleness(modelled.y, r);
//  warpedFractal.amplitude *= 0.2 + (1-poleness) * 0.8;
  
  float4 noised = 0;//sample_terrain(modelled.xyz, warpedFractal);
  for (int i = 0; i < 1; i++) {
    float3 craterPosition = normalize(float3(0, 1, -0.2))*r;
    float4 cr = crater(modelled.xyz, craterPosition, 100, 0.02);
    noised += cr;
  }
  
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
