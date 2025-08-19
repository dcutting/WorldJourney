#include <metal_stdlib>

#include "../Shared/InfiniteNoise.h"
#include "../Shared/Noise.h"
#include "../Shared/GridPosition.h"

using namespace metal;

float4 sharp_abs(float4 a) {
  float h = abs(a.x);
  float3 d = a.x < 0 ? -a.yzw : a.yzw;
  return float4(h, d);
}

float4 billow_from_basic(float4 basic) {
  return sharp_abs(basic);
}

float4 ridge_from_billow(float4 billow) {
  return float4(1 - billow.x, -billow.yzw);
}

float4 fbmInf3old(int3 cubeOrigin, int cubeSize, float3 x, float freq, float ampl, float octaves, float sharpness, float epsilon) {
  float tp = 0.0;
  float3 derivativep(0);
  float t = 0.0;
  float3 derivative(0);
  float3 slopeErosionDerivative = float3(0.0);
  float3 slopeErosionGradient = 0;

  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  for (int i = 0; i < maxO; i++) {
    
    // f = 1.7          f = 1
    // cubeOrigin = 2   cubeOrigin = -64,0,-64
    // cubeSize = 2     cubeSize = 64
    // x = 0.9          x = 0,0,0
    
    int fi = floor(freq);                   // 1      // 1
    float ff = fract(freq);                 // 0.7    // 0
    int3 cofi = cubeOrigin * fi;            // 2      // -64,0,-64
    float3 coff = (float3)cubeOrigin * ff;  // 1.4    // 0,0,0
    int3 coffi = (int3)floor(coff);         // 1      // 0,0,0
    float3 cofr = fract(coff);              // 0.4    // 0,0,0
    int3 cop = cofi + coffi;                // 3      // -64,0,-64

    float3 xf = x * freq;                   // 1.53   // 0,0,0
    int3 xfi = (int3)floor(xf);             // 1      // 0,0,0
    float3 xff = fract(xf);                 // 0.53   // 0,0,0
    int3 xfic = xfi * cubeSize;             // 2      // 0,0,0
    float3 xffc = xff * cubeSize;           // 1.06   // 0,0,0
    int3 xffci = (int3)floor(xffc);         // 1      // 0,0,0
    float3 xffcf = fract(xffc);             // 0.06   // 0,0,0
    int3 xfcop = xfic + xffci;              // 3      // 0,0,0
    
    float3 fc = cofr + xffcf;               // 0.46   // 0,0,0
    int3 fci = (int3)floor(fc);             // 0      // 0,0,0
    float3 fcf = fract(fc);                 // 0.46   // 0,0,0
    
    int3 c0 = cop + xfcop + fci;            // 6      // -64,0,-64
    float3 t0 = fcf;                        // 0.46   // 0,0,0

    float4 basic = vNoised3(c0, t0);

    basic.yzw *= freq;
    float4 combined;
    float4 billow = billow_from_basic(basic);
    if (sharpness <= 0.0) {
      combined = mix(basic, billow, abs(sharpness));
    } else {
      float4 ridge = ridge_from_billow(billow);
      combined = mix(basic, ridge, sharpness);
    }
    combined *= ampl;
    
    tp = t;
    derivativep = derivative;
    
    t += combined.x;
    derivative += combined.yzw;

    float persistence = 0.5;

    float slopeErosionFactor = 1.0;

    float altitudeErosion = persistence;  // todo: add concavity erosion.
    slopeErosionDerivative += basic.yzw;
    slopeErosionGradient += slopeErosionDerivative * slopeErosionFactor;
    float slopeErosion = 1.0 / (1.0 + dot(slopeErosionGradient, slopeErosionGradient));
    ampl *= altitudeErosion * slopeErosion;

    // TODO: update derivative.

    freq *= 2;

    if (abs(combined.x) < epsilon) {
      break;
    }
  }
  
  return mix(float4(tp, derivativep), float4(t, derivative), mixO);
}

GridPosition noise3_ImproveXZ(GridPosition p) {
  GridPosition x = getX(p);
  GridPosition y = getY(p);
  GridPosition z = getZ(p);
  GridPosition xz = addGridPosition(x, z);
  GridPosition s2 = multiplyGridPosition(xz, -0.211324865405187);
  GridPosition yy = multiplyGridPosition(y, 0.577350269189626);
  GridPosition s2yy = addGridPosition(s2, yy);
  GridPosition xr = addGridPosition(x, s2yy);
  GridPosition zr = addGridPosition(z, s2yy);
  GridPosition yr = addGridPosition(multiplyGridPosition(xz, -0.577350269189626), yy);

  return makeGridPosition(int3(xr.i.x, yr.i.x, zr.i.x), float3(xr.f.x, yr.f.x, zr.f.x));

//  double xz = x + z;
//  double s2 = xz * -0.211324865405187;
//  double yy = y * 0.577350269189626;
//  double xr = x + (s2 + yy);
//  double zr = z + (s2 + yy);
//  double yr = xz * -0.577350269189626 + yy;
//
//  Generate noise on coordinate xr, yr, zr
}

float4 fbmRegular(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 1.9;
  float gain = 0.49;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  float4 previous = 0;
  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  for (int i = 0; i < maxO; i++) {
    // h = a * f(s * x)
    // d = a * (f(s * x))'
    //   = a * s * f'(s * x)

    GridPosition p = multiplyGridPosition(initial, frequency);
    p.i.y += 100; // TODO: Like a seed?
    float4 noise = vNoised3(p.i, p.f);

    previous = float4(height, derivative);
    height += amplitude * noise.x;
    derivative += amplitude * frequency * noise.yzw;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  float4 next = float4(height, derivative);
  return mix(previous, next, mixO);
}

float4 fbmSquared(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 1.9;
  float gain = 0.49;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  float4 previous = 0;
  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  for (int i = 0; i < maxO; i++) {
    // h = a * f(sx)^2
    // d = a(f(sx)f(sx)'+f(sx)'f(sx))
    //   = 2af(sx)f(sx)'
    //   = 2asf(sx)f'(sx)

    GridPosition p = multiplyGridPosition(initial, frequency);
    float4 noise = vNoised3(p.i, p.f);

    previous = float4(height, derivative);
    height += amplitude * noise.x * noise.x;
    derivative += 2 * amplitude * frequency * noise.x * noise.yzw;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  float4 next = float4(height, derivative);
  return mix(previous, next, mixO);
}

float4 fbmCubed(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 1.9;
  float gain = 0.49;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  float4 previous = 0;
  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  for (int i = 0; i < maxO; i++) {
    // h = a * f(sx)^3
    // d = 3asf(sx)^2f'(sx)

    GridPosition p = multiplyGridPosition(initial, frequency);
    Noise noise = vNoisedd3(p.i, p.f);

    previous = float4(height, derivative);
    height += amplitude * noise.v * noise.v * noise.v;
    derivative += 3 * amplitude * frequency * noise.v * noise.v * noise.d;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  float4 next = float4(height, derivative);
  return mix(previous, next, mixO);
}

float4 fbmEroded(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 1.9;
  float gain = 0.49;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  float4 previous = 0;
  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  for (int i = 0; i < maxO; i++) {
    // h  = af(sx) / (1 + (asf'(sx)).(asf'(sx)))
    //    = v / (1 + dd)
    // d  = ((1+dd).v' - v.(1+dd)') / (1+dd)^2
    //    = ((1+dd).v' - v.( )) / (1+dd)^2
    // d  = ((1 + (asf'(sx)).(asf'(sx))) * (af(sx))' - af(sx) * (1 + (asf'(sx)).(asf'(sx)))') / (1 + (asf'(sx)).(asf'(sx)))^2
    //    = (t1 - t2) / t5
    // t1 = (1 + (asf'(sx)).(asf'(sx))) * (af(sx))'
    //    = (1 + (asf'(sx)).(asf'(sx))) * asf'(sx)
    //    = asf'(sx) + asf'(sx).asf'(sx).asf'(sx)
    // t2 = af(sx) * (1 + (asf'(sx)).(asf'(sx)))'
    //    = t3 * t4
    // t3 = af(sx)
    // t4 = (1 + (asf'(sx)).(asf'(sx)))'
    //    = 0 + ((asf'(sx)).(asf'(sx)))'
    //    = asf'(sx).(as^2f''(sx)) + (as^2f''(sx)).asf'(sx)
    //    = 2 * asf'(sx).(as^2f''(sx))
    // t5 = (1 + (asf'(sx)).(asf'(sx)))^2
    // d  =
    // d = (1 + (a * s * f'(s * x)).(a * s * f'(s * x))) * a * s * f'(s * x)
    //      - (a * f(s * x)) * (a s f'(s x)).(a s^2 f''(s x)) + (a s^2 f''(s x)).(a s f'(s x))
    //      / ((1 + (a * s * f'(s * x)).(a * s * f'(s * x))) * (1 + (a * s * f'(s * x)).(a * s * f'(s * x))))

    previous = float4(height, derivative);

    GridPosition p = multiplyGridPosition(initial, frequency);
    Noise noise = vNoisedd3(p.i, p.f);
    float oV = noise.v * amplitude;
    float3 oD = noise.d * frequency * amplitude;
    float3x3 oDD = noise.dd * frequency * frequency * amplitude;

    float S_i = dot(oD, oD);
    float E_i = 1.0 / (1.0 + S_i);

    height += oV * E_i;

    float3 td1 = oD * E_i;
    float3 dS_i_dp = 2.0 * (oD * oDD);
    float3 dE_i_dp = -E_i * E_i * dS_i_dp;
    float3 t2d = oV * dE_i_dp;

    derivative += td1 + t2d;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  float4 next = float4(height, derivative);
  return mix(previous, next, mixO);
}

float4 swissTurbulence(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 1.9;
  float gain = 0.49;
  float amplitude = 1.0;

  float height = 0;
  float3 derivative = 0;

  float4 previous = 0;
  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  for (int i = 0; i < maxO; i++) {
    previous = float4(height, derivative);

    // h = (1 - ((k * abs(noise.x * noise.x * noise.x))/(1 + k * noise.x * noise.x))) * a
    // d = (a * k * s * noise.x * abs(noise.x) * (-k * noise.x * noise.x - 3) * noise.yzw)/((k * noise.x * noise.x + 1) * (k * noise.x * noise.x + 1))
    GridPosition p = multiplyGridPosition(initial, frequency);
    float4 noise = vNoised3(p.i, p.f);

    float a = amplitude;
    float s = frequency;
    float k = 30;

    float h = (1 - ((k * abs(noise.x * noise.x * noise.x))/(1 + k * noise.x * noise.x))) * a;
    float3 d = (a * k * s * noise.x * abs(noise.x) * (-k * noise.x * noise.x - 3) * noise.yzw)/((k * noise.x * noise.x + 1) * (k * noise.x * noise.x + 1));

    height += h;
    derivative += d;

    frequency *= lacunarity;
    amplitude *= gain * saturate(height);
  }
  
  return mix(previous, float4(height, derivative), mixO);
}

float4 jordanTurbulence(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 1.9345696;
  float gain1 = 0.8;
  float gain = 0.5167590;
  float warp0 = 0.4;
  float warp = 0.35;
  float damp0 = 1.0;
  float damp = 0.8;
  float damp_scale = 1;

  float amp = gain1;
  float freq = frequency;
  float damped_amp = amp * gain;

  GridPosition p = multiplyGridPosition(initial, freq);

  float4 previous = 0;
  float mixO = fract(octaves);
  int maxO = ceil(octaves);

  float4 noise = vNoised3(p.i, p.f);
  float4 n2 = noise * noise.x;
  float3 derivative = 2 * damped_amp * freq * noise.x * noise.yzw;
  float height = n2.x;
  float3 dsum_warp = warp0*n2.yzw;
  float3 dsum_damp = damp0*n2.yzw;

  for (int i = 1; i < maxO; i++) {
    previous = float4(height, derivative);

    GridPosition j = addGridPosition(multiplyGridPosition(p, freq), makeGridPosition(float3(dsum_warp.x, 0, dsum_warp.y)));
    noise = vNoised3(j.i, j.f);
    n2 = noise * noise.x;
    derivative += 2 * n2.yzw * freq * damped_amp;
    height += damped_amp * n2.x;
    dsum_warp += warp * n2.yzw;
    dsum_damp += damp * n2.yzw;
    freq *= lacunarity;
    amp *= gain;
    damped_amp = amp * (1-damp_scale/(1+dot(dsum_damp,dsum_damp)));
  }

  return mix(previous, float4(height, derivative), mixO);
}

// r = f(p)
// r' = f'(p)
// r = f(p + g(p))
// r' = (g'(p) + 1) * f'(p + g(p))
// g(p) = k * [h(p + x), 0, h(p + y)]
// g'(p) = (kh'(p+x), 0, kh'(p+y))
//template <typename Func>
float4 fbmWarped(GridPosition initial, float frequency, float octaves, float warpFrequency, float warpOctaves, float warpFactor) {
//}, FuncWrapper<Func> wrapper) {

  GridPosition p = initial;
  GridPosition p1 = makeGridPosition(float3(3.1, 2.3, 4.3));
  GridPosition p2 = makeGridPosition(float3(1.2, 6.6, 0.7));
  GridPosition p3 = makeGridPosition(float3(8.4, 8.9, 2.3));
  float4 hx = fbmRegular(addGridPosition(p, p1), warpFrequency, warpOctaves);
  float4 hy = fbmRegular(addGridPosition(p, p2), warpFrequency, warpOctaves);
  float4 hz = fbmRegular(addGridPosition(p, p3), warpFrequency, warpOctaves);
  GridPosition q = makeGridPosition(float3(hx.x, hy.x, hz.x));
  GridPosition z = addGridPosition(p, multiplyGridPosition(q, warpFactor));
  float4 t = fbmCubed(z, frequency, octaves);

  float3x3 i = float3x3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
  float3x3 j = float3x3(hx.yzw, hy.yzw, hz.yzw);
  float3 d = t.yzw * (i + j * warpFactor);
  float4 result = float4(t.x, d);

  return result;
}
