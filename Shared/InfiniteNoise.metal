#include <metal_stdlib>

#include "../Shared/InfiniteNoise.h"
#include "../Shared/Noise.h"
#include "../Shared/GridPosition.h"

using namespace metal;

constant float3 gradient_table[] = {
  float3(-0.299, 0.275, 0.268),
  float3(-0.857, -0.468, 0.316),
  float3(-0.028, -0.139, 0.567),
  float3(0.640, 0.183, -0.834),
  float3(0.155, -0.085, 0.753),
  float3(-0.408, -0.815, -0.154),
  float3(-0.646, -0.598, 0.615),
  float3(0.464, -0.988, -0.657),
  float3(0.452, 0.117, 0.642),
  float3(-0.098, -0.764, 0.187),
  float3(-0.942, 0.000, 0.071),
  float3(-0.272, -0.505, 0.288),
  float3(0.701, 0.520, 0.197),
  float3(-0.772, 0.347, -0.851),
  float3(0.357, -0.422, -0.665),
  float3(-0.071, 0.991, 0.287),
  float3(0.907, 0.725, -0.710),
  float3(-0.935, -0.583, 0.380),
  float3(-0.415, 0.045, -0.041),
  float3(-0.297, 0.623, -0.407)
};

float4 gradient_noise_inner(int3 cube_pos0, int3 cube_pos1, float3 t0, float3 t1)
{
  int x0 = cube_pos0.x;
  int y0 = cube_pos0.y;
  int z0 = cube_pos0.z;
  
  int x1 = cube_pos1.x;
  int y1 = cube_pos1.y;
  int z1 = cube_pos1.z;
  
  const int NOISE_HASH_X = 1213;
  const int NOISE_HASH_Y = 6203;
  const int NOISE_HASH_Z = 5237;
  const int NOISE_HASH_SEED = 1039;
  int ox0 = NOISE_HASH_X * x0 + NOISE_HASH_SEED;
  int oy0 = NOISE_HASH_Y * y0;
  int oz0 = NOISE_HASH_Z * z0;
  int ox1 = NOISE_HASH_X * x1 + NOISE_HASH_SEED;
  int oy1 = NOISE_HASH_Y * y1;
  int oz1 = NOISE_HASH_Z * z1;
  
  const int NOISE_HASH_SHIFT = 13;
  int index0 = ox0 + oy0 + oz0;
  int index1 = ox1 + oy0 + oz0;
  int index2 = ox0 + oy1 + oz0;
  int index3 = ox1 + oy1 + oz0;
  int index4 = ox0 + oy0 + oz1;
  int index5 = ox1 + oy0 + oz1;
  int index6 = ox0 + oy1 + oz1;
  int index7 = ox1 + oy1 + oz1;
  index0 ^= (index0 >> NOISE_HASH_SHIFT);
  index1 ^= (index1 >> NOISE_HASH_SHIFT);
  index2 ^= (index2 >> NOISE_HASH_SHIFT);
  index3 ^= (index3 >> NOISE_HASH_SHIFT);
  index4 ^= (index4 >> NOISE_HASH_SHIFT);
  index5 ^= (index5 >> NOISE_HASH_SHIFT);
  index6 ^= (index6 >> NOISE_HASH_SHIFT);
  index7 ^= (index7 >> NOISE_HASH_SHIFT);
  index0 &= 0xFF;
  index1 &= 0xFF;
  index2 &= 0xFF;
  index3 &= 0xFF;
  index4 &= 0xFF;
  index5 &= 0xFF;
  index6 &= 0xFF;
  index7 &= 0xFF;
  
  float3 ga = normalize(gradient_table[index0 % 20]); // TODO: fix with more gradients (not % 20)).
  float3 gb = normalize(gradient_table[index1 % 20]);
  float3 gc = normalize(gradient_table[index2 % 20]);
  float3 gd = normalize(gradient_table[index3 % 20]);
  float3 ge = normalize(gradient_table[index4 % 20]);
  float3 gf = normalize(gradient_table[index5 % 20]);
  float3 gg = normalize(gradient_table[index6 % 20]);
  float3 gh = normalize(gradient_table[index7 % 20]);
  
  // Project permuted fractionals onto gradient vector
  float va = dot(ga, select(t0, t1, (bool3){ false, false, false }));
  float vb = dot(gb, select(t0, t1, (bool3){ true, false, false }));
  float vc = dot(gc, select(t0, t1, (bool3){ false, true, false }));
  float vd = dot(gd, select(t0, t1, (bool3){ true, true, false }));
  float ve = dot(ge, select(t0, t1, (bool3){ false, false, true }));
  float vf = dot(gf, select(t0, t1, (bool3){ true, false, true }));
  float vg = dot(gg, select(t0, t1, (bool3){ false, true, true }));
  float vh = dot(gh, select(t0, t1, (bool3){ true, true, true }));
  
  float3 f = t0;
  float3 u = f*f*f*(f*(f*6.0-15.0)+10.0);
  float3 du = 30.0*f*f*(f*(f-2.0)+1.0);
  
  float value = va + u.x*(vb-va) + u.y*(vc-va) + u.z*(ve-va) + u.x*u.y*(va-vb-vc+vd) + u.y*u.z*(va-vc-ve+vg) + u.z*u.x*(va-vb-ve+vf) + (-va+vb+vc-vd+ve-vf-vg+vh)*u.x*u.y*u.z;
  value = value;
  return float4( value,
               ga + u.x*(gb-ga) + u.y*(gc-ga) + u.z*(ge-ga) + u.x*u.y*(ga-gb-gc+gd) + u.y*u.z*(ga-gc-ge+gg) + u.z*u.x*(ga-gb-ge+gf) + (-ga+gb+gc-gd+ge-gf-gg+gh)*u.x*u.y*u.z +   // derivatives
               du * (float3(vb,vc,ve) - va + u.yzx*float3(va-vb-vc+vd,va-vc-ve+vg,va-vb-ve+vf) + u.zxy*float3(va-vb-ve+vf,va-vb-vc+vd,va-vc-ve+vg) + u.yzx*u.zxy*(-va+vb+vc-vd+ve-vf-vg+vh) ));
}

float4 sharp_abs(float4 a) {
  float h = abs(a.x);
  float3 d = a.x < 0 ? -a.yzw : a.yzw;
  return float4(h, d);
}

float4 makeBillowFromBasic(float4 basic, float k) {
  return sharp_abs(basic);
}

float4 makeRidgeFromBillow(float4 billow) {
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
    int3 c1 = c0 + 1;                       // 7      // -63, 1, -63
    float3 t0 = fcf;                        // 0.46   // 0,0,0
    float3 t1 = t0 - 1;                     // -0.54  // -1, -1, -1
    
    float4 basic = vNoised3(c0, t0);
//    float4 basic = gradient_noise_inner(c0, c1, t0, t1);

    basic.yzw *= freq;
    float4 combined;
    float4 billow = makeBillowFromBasic(basic, 0.01); // todo: k should probably be based upon the octave.
    if (sharpness <= 0.0) {
      combined = mix(basic, billow, abs(sharpness));
    } else {
      float4 ridge = makeRidgeFromBillow(billow);
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
  float lacunarity = 2;
  float gain = 0.5;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  for (int i = 0; i < ceil(octaves); i++) {
    // h = a * f(s * x)
    // d = a * (f(s * x))'
    //   = a * s * f'(s * x)

    GridPosition p = multiplyGridPosition(initial, frequency);
    Noise noise = vNoisedd3(p.i, p.f);

    height += amplitude * noise.v;
    derivative += amplitude * frequency * noise.d;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  return float4(height, derivative);
}

float4 fbmSquared(GridPosition initial, float frequency, int octaves) {
  float lacunarity = 2;
  float gain = 0.5;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  for (int i = 0; i < octaves; i++) {
    // h = a * f(sx)^2
    // d = a(f(sx)f(sx)'+f(sx)'f(sx))
    //   = 2af(sx)f(sx)'
    //   = 2asf(sx)f'(sx)

    GridPosition p = multiplyGridPosition(initial, frequency);
    float4 noise = vNoised3(p.i, p.f);

    height += amplitude * noise.x * noise.x;
    derivative += 2 * amplitude * frequency * noise.x * noise.yzw;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  return float4(height, derivative);
}

float4 fbmCubed(GridPosition initial, float frequency, int octaves) {
  float lacunarity = 2;
  float gain = 0.5;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  for (int i = 0; i < octaves; i++) {
    GridPosition p = multiplyGridPosition(initial, frequency);
    float4 noise = vNoised3(p.i, p.f);

    height += amplitude * noise.x * noise.x * noise.x;
    derivative += 3 * amplitude * frequency * noise.x * noise.x * noise.yzw;

    amplitude *= gain;
    frequency *= lacunarity;
  }

  return float4(height, derivative);
}

float4 eroded(GridPosition initial, float frequency, float octaves) {
  float lacunarity = 2;
  float gain = 0.5;
  float amplitude = 1;

  float height = 0;
  float3 derivative = 0;

  for (int i = 0; i < ceil(octaves); i++) {
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

  return float4(height, derivative);
}

float4 swissTurbulence(GridPosition initial, float frequency, int octaves) {
  float lacunarity = 1.9431;
  float gain = 0.51319;
  float warp = 4000;
  float amplitude = 1.0;

  float height = 0;
  float3 derivative = 0;

  for (int i = 0; i < octaves; i++) {
    // p = (initial + warp * derivative) * frequency
    GridPosition p = multiplyGridPosition(addGridPosition(initial, makeGridPosition(warp * derivative)), frequency);
//    GridPosition p = multiplyGridPosition(initial, frequency);
    Noise noise = vNoisedd3(p.i, p.f);
    float4 absnvd = sharp_abs(float4(noise.v, noise.d));

    // h = af(s(x+w))

    float4 jordan = fbmRegular(p, 10, i == 0 ? 8 : 0) * 0.00001;
    height += (1 - absnvd.x) * amplitude + jordan.x;
    derivative += -absnvd.yzw * frequency * amplitude + jordan.yzw; // TODO: consider offset of p.

    frequency *= lacunarity;
    amplitude *= gain * saturate(height);
  }
  return float4(height, derivative);
}

float4 jordanTurbulence(GridPosition initial, float frequency, int octaves) {
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

  float4 n = vNoised3(p.i, p.f);
  float4 n2 = n * n.x;
  float3 d = 2 * n2.yzw * freq * damped_amp;
  float sum = n2.x * damped_amp;
  float3 dsum_warp = warp0*n2.yzw;
  float3 dsum_damp = damp0*n2.yzw;

  for(int i=1; i < octaves; i++) {
//    GridPosition j = addGridPosition(multiplyGridPosition(p, freq), makeGridPosition(float3(dsum_warp.x, 0, dsum_warp.y)));
    GridPosition j = multiplyGridPosition(p, freq);
    n = vNoised3(j.i, j.f);
    n2 = n * n.x;
    d += 2 * n2.yzw * freq * damped_amp;
    sum += damped_amp * n2.x;
    dsum_warp += warp * n2.yzw;
    dsum_damp += damp * n2.yzw;
    freq *= lacunarity;
    amp *= gain;
    damped_amp = amp * (1-damp_scale/(1+dot(dsum_damp,dsum_damp)));
  }
  return float4(sum, d);
}

// 3D FBM function with fake erosion modification to height, and its analytic derivative
float4 gemini(GridPosition initial, float frequency, uint octaves) {
  float lacunarity = 2.0;
  float persistence = 0.5;
  float totalHeight = 0.0;
  float3 totalDerivative = 0.0; // Accumulates derivative of the *eroded* FBM
  float amplitude = 1.0;
  float maxValue = 0.0; // For normalizing the final height

  for (uint i = 0; i < octaves; ++i) {
    // Get noise value, first derivative, and second derivative for this octave
    GridPosition p = multiplyGridPosition(initial, frequency);
    Noise octaveNoise = vNoisedd3(p.i, p.f);

    // Scale the base noise value and its derivatives by current amplitude and frequency
    float currentNoiseValue = octaveNoise.v * amplitude;
    float3 currentNoiseGradient = octaveNoise.d * amplitude * frequency;
    float3x3 currentNoiseHessian = octaveNoise.dd * amplitude * (frequency * frequency); // Scale hessian by A * F^2

    // --- Calculate Erosion Factor for Height (E_i) ---
    float S_i = dot(currentNoiseGradient, currentNoiseGradient); // S_i = d_i . d_i
    float E_i = 1.0 / (1.0 + S_i); // E_i = 1 / (1 + S_i)

    // Accumulate Eroded Height
    totalHeight += currentNoiseValue * E_i;

    // --- Calculate Derivative of Eroded Height for this Octave (d/dp [H_eroded_i]) ---
    // H_eroded_i = currentNoiseValue * E_i
    // d/dp [H_eroded_i] = (d/dp [currentNoiseValue]) * E_i + currentNoiseValue * (d/dp [E_i])

    // Term 1: (d/dp [currentNoiseValue]) * E_i
    // d/dp [currentNoiseValue] is just currentNoiseGradient (derivative of N_value * A)
    float3 term1_derivative = currentNoiseGradient * E_i;

    // Term 2: currentNoiseValue * (d/dp [E_i])
    // d/dp [E_i] = -1 * (1 + S_i)^(-2) * d/dp [S_i] = -E_i^2 * d/dp [S_i]
    // d/dp [S_i] = d/dp [dot(d_i, d_i)]
    // In 3D: d/dp [dot(d_i, d_i)] = 2 * (d_i * Hessian(N_i))
    float3 dS_i_dp = 2.0 * (currentNoiseGradient * currentNoiseHessian); // This is a float3 vector (dx, dy, dz)

    float3 dE_i_dp = -E_i * E_i * dS_i_dp;

    float3 term2_derivative = currentNoiseValue * dE_i_dp;

    // Sum the derivative contributions for this octave
    totalDerivative += term1_derivative + term2_derivative;

    maxValue += amplitude; // Sum of original amplitudes for rough normalization

    frequency *= lacunarity;
    amplitude *= persistence;
  }

  // Normalize the accumulated height.
  // Note: Normalizing `totalHeight` by `maxValue` might not perfectly map
  // to [-1, 1] anymore due to the erosion factor, but it's a common starting point.
  totalHeight /= maxValue;

  return float4(totalHeight, totalDerivative);
}

//float4 fbmGP3(GridPosition initial, float frequency, float octaves) {
//  GridPosition p = multiplyGridPosition(initial, frequency);
//
////  GridPosition p1 = makeGridPosition(float3(3.1, 0, 4.3));
////  GridPosition p2 = makeGridPosition(float3(1.2, 0, 0.7));
////
////  float qx = fbmRegular(addGridPosition(p, p1), 0.001, 2).x;
////  float qz = fbmRegular(addGridPosition(p, p2), 0.001, 2).x;
////
////  GridPosition q = makeGridPosition(float3(qx, 0, qz));
////  GridPosition r = addGridPosition(p, multiplyGridPosition(q, 0.3));
//
//  GridPosition r = p;
//
////  return jordanTurbulence(r, frequency, octaves);
//  return fbmRegular(r, frequency, octaves);
//}

//#ifdef WARPED
//
//float4 fbmInf3(int3 cubeOrigin, int cubeSize, float3 x, float frequency, float amplitude, float octaves, float sharpness, float epsilon) {
//  GridPosition origin = { cubeOrigin, 0 };
//  GridPosition offset = makeGridPosition(x * cubeSize);
//  GridPosition initial = addGridPosition(origin, offset);
//
//  GridPosition p = initial;
//
//  GridPosition p1 = makeGridPosition(float3(3.1, 0, 4.3));
//  GridPosition p2 = makeGridPosition(float3(1.2, 0, 0.7));
//
//  float qx = fbmGP3(addGridPosition(p, p1), 0.01, 4, 4).x;
//  float qz = fbmGP3(addGridPosition(p, p2), 0.01, 4, 4).x;
//
//  GridPosition q = makeGridPosition(float3(qx, 0, qz));
//
//  GridPosition q1 = makeGridPosition(float3(1.7, 0, 9.2));
//  GridPosition q2 = makeGridPosition(float3(8.3, 0, 2.8));
//
//  float rx = fbmGP3(addGridPosition(p, addGridPosition(q1, multiplyGridPosition(q, 8))), 0.001, 4, 4).x;
//  float rz = fbmGP3(addGridPosition(p, addGridPosition(q2, multiplyGridPosition(q, 8))), 0.001, 4, 4).x;
//
//  GridPosition r = makeGridPosition(float3(rx, 0, rz));
//
//  GridPosition z = addGridPosition(p, multiplyGridPosition(r, 20));
//
//  return fbmGP3(z, frequency, amplitude, octaves);
//}
//
//#else
//
//float4 fbmInf3(int3 cubeOrigin, int cubeSize, float3 x, float frequency, float amplitude, float octaves, float sharpness, float epsilon) {
//  return fbmGP3(initial, frequency, octaves);
//}
//
//#endif

#if 0

#include <metal_stdlib>
using namespace metal;

// Struct to hold the noise value, its 2D gradient, and its 2D Hessian matrix
struct NoiseResult {
    float value;
    float2 derivative; // (dN/dx, dN/dy)
    float2x2 hessian;  // The 2x2 Hessian matrix
};

// ASSUMPTION: This function exists and provides value, gradient, and Hessian
// for your base noise (e.g., Perlin, Simplex noise).
// Example: NoiseResult noise(float2 p) { /* ... implementation ... */ }
NoiseResult noise(float2 p); // Declaration only

// Struct to hold the FBM height and its 2D derivative
struct FBMResult {
    float height;
    float2 derivative; // This is now the derivative of the *eroded* FBM
};

// FBM function with fake erosion modification to height, and its analytic derivative
FBMResult fbm(float2 p, uint octaves, float lacunarity, float persistence) {
    float totalHeight = 0.0;
    float2 totalDerivative = 0.0; // Accumulates derivative of the *eroded* FBM
    float frequency = 1.0;
    float amplitude = 1.0;
    float maxValue = 0.0; // For normalizing the final height

    for (uint i = 0; i < octaves; ++i) {
        // Get noise value, first derivative, and second derivative for this octave
        NoiseResult octaveNoise = noise(p * frequency);

        // Scale the base noise value and its derivatives by current amplitude and frequency
        float currentNoiseValue = octaveNoise.value * amplitude;
        float2 currentNoiseGradient = octaveNoise.derivative * amplitude * frequency;
        float2x2 currentNoiseHessian = octaveNoise.hessian * amplitude * (frequency * frequency); // Scale hessian by A * F^2

        // --- Calculate Erosion Factor for Height (E_i) ---
        float S_i = dot(currentNoiseGradient, currentNoiseGradient); // S_i = d_i . d_i
        float E_i = 1.0 / (1.0 + S_i); // E_i = 1 / (1 + S_i)

        // Accumulate Eroded Height
        totalHeight += currentNoiseValue * E_i;

        // --- Calculate Derivative of Eroded Height for this Octave (d/dp [H_eroded_i]) ---
        // H_eroded_i = currentNoiseValue * E_i
        // d/dp [H_eroded_i] = (d/dp [currentNoiseValue]) * E_i + currentNoiseValue * (d/dp [E_i])

        // Term 1: (d/dp [currentNoiseValue]) * E_i
        // d/dp [currentNoiseValue] is just currentNoiseGradient (derivative of N_value * A)
        float2 term1_derivative = currentNoiseGradient * E_i;

        // Term 2: currentNoiseValue * (d/dp [E_i])
        // d/dp [E_i] = -1 * (1 + S_i)^(-2) * d/dp [S_i] = -E_i^2 * d/dp [S_i]
        // d/dp [S_i] = d/dp [dot(d_i, d_i)]
        // If d_i is a vector, d/dp[dot(d_i, d_i)] = 2 * transpose(d_i) * (Jacobian of d_i wrt p)
        // Here, Jacobian of d_i wrt p is currentNoiseHessian
        // So, d/dp [S_i] = 2 * (currentNoiseGradient * currentNoiseHessian)  (vector * matrix mult)
        float2 dS_i_dp = 2.0 * (currentNoiseGradient * currentNoiseHessian); // This is a float2 vector (dx, dy)

        float2 dE_i_dp = -E_i * E_i * dS_i_dp;

        float2 term2_derivative = currentNoiseValue * dE_i_dp;

        // Sum the derivative contributions for this octave
        totalDerivative += term1_derivative + term2_derivative;

        maxValue += amplitude; // Sum of original amplitudes for rough normalization

        frequency *= lacunarity;
        amplitude *= persistence;
    }

    // Normalize the accumulated height.
    // Note: Normalizing `totalHeight` by `maxValue` might not perfectly map
    // to [-1, 1] anymore due to the erosion factor, but it's a common starting point.
    totalHeight /= maxValue;

    return FBMResult{ .height = totalHeight, .derivative = totalDerivative };
}

/*
// Example of how you might use it in a kernel (conceptual)
kernel void myComputeKernel(
    texture2d<float, access::write> outputHeightMap [[texture(0)]],
    texture2d<float2, access::write> outputDerivativeMap [[texture(1)]],
    uint2 gid [[thread_position_in_grid]],
    constant float2& scaleFactor [[buffer(0)]],
    constant uint& octaves [[buffer(1)]],
    constant float& lacunarity [[buffer(2)]],
    constant float& persistence [[buffer(3)]]
) {
    float2 uv = float2(gid) / float2(outputHeightMap.get_width(), outputHeightMap.get_height());
    float2 p = uv * scaleFactor;

    FBMResult result = fbm(p, octaves, lacunarity, persistence);

    // Output eroded height
    outputHeightMap.write(float4((result.height + 1.0) * 0.5), gid);

    // Output derivative of the *eroded* FBM
    outputDerivativeMap.write(float4(result.derivative, 0.0, 1.0), gid);
}
*/

#include <metal_stdlib>
using namespace metal;

// Struct to hold the noise value, its 3D gradient, and its 3D Hessian matrix
struct NoiseResult {
    float value;
    float3 derivative; // (dN/dx, dN/dy, dN/dz)
    float3x3 hessian;  // The 3x3 Hessian matrix: [[d2N/dx2, d2N/dxdy, d2N/dxdz], ...]
};

// ASSUMPTION: This function exists and provides value, gradient, and Hessian
// for your 3D base noise (e.g., Perlin, Simplex noise).
// Example: NoiseResult noise(float3 p) { /* ... implementation ... */ }
NoiseResult noise(float3 p); // Declaration only

// Struct to hold the 3D FBM height and its 3D derivative
struct FBMResult {
    float height;
    float3 derivative; // This is the derivative of the *eroded* FBM in 3D
};

// 3D FBM function with fake erosion modification to height, and its analytic derivative
FBMResult fbm(float3 p, uint octaves, float lacunarity, float persistence) {
    float totalHeight = 0.0;
    float3 totalDerivative = 0.0; // Accumulates derivative of the *eroded* FBM
    float frequency = 1.0;
    float amplitude = 1.0;
    float maxValue = 0.0; // For normalizing the final height

    for (uint i = 0; i < octaves; ++i) {
        // Get noise value, first derivative, and second derivative for this octave
        NoiseResult octaveNoise = noise(p * frequency);

        // Scale the base noise value and its derivatives by current amplitude and frequency
        float currentNoiseValue = octaveNoise.value * amplitude;
        float3 currentNoiseGradient = octaveNoise.derivative * amplitude * frequency;
        float3x3 currentNoiseHessian = octaveNoise.hessian * amplitude * (frequency * frequency); // Scale hessian by A * F^2

        // --- Calculate Erosion Factor for Height (E_i) ---
        float S_i = dot(currentNoiseGradient, currentNoiseGradient); // S_i = d_i . d_i
        float E_i = 1.0 / (1.0 + S_i); // E_i = 1 / (1 + S_i)

        // Accumulate Eroded Height
        totalHeight += currentNoiseValue * E_i;

        // --- Calculate Derivative of Eroded Height for this Octave (d/dp [H_eroded_i]) ---
        // H_eroded_i = currentNoiseValue * E_i
        // d/dp [H_eroded_i] = (d/dp [currentNoiseValue]) * E_i + currentNoiseValue * (d/dp [E_i])

        // Term 1: (d/dp [currentNoiseValue]) * E_i
        // d/dp [currentNoiseValue] is just currentNoiseGradient (derivative of N_value * A)
        float3 term1_derivative = currentNoiseGradient * E_i;

        // Term 2: currentNoiseValue * (d/dp [E_i])
        // d/dp [E_i] = -1 * (1 + S_i)^(-2) * d/dp [S_i] = -E_i^2 * d/dp [S_i]
        // d/dp [S_i] = d/dp [dot(d_i, d_i)]
        // In 3D: d/dp [dot(d_i, d_i)] = 2 * (d_i * Hessian(N_i))
        float3 dS_i_dp = 2.0 * (currentNoiseGradient * currentNoiseHessian); // This is a float3 vector (dx, dy, dz)

        float3 dE_i_dp = -E_i * E_i * dS_i_dp;

        float3 term2_derivative = currentNoiseValue * dE_i_dp;

        // Sum the derivative contributions for this octave
        totalDerivative += term1_derivative + term2_derivative;

        maxValue += amplitude; // Sum of original amplitudes for rough normalization

        frequency *= lacunarity;
        amplitude *= persistence;
    }

    // Normalize the accumulated height.
    // Note: Normalizing `totalHeight` by `maxValue` might not perfectly map
    // to [-1, 1] anymore due to the erosion factor, but it's a common starting point.
    totalHeight /= maxValue;

    return FBMResult{ .height = totalHeight, .derivative = totalDerivative };
}

/*
// Example of how you might use it in a kernel (conceptual, e.g., for a 3D texture or volume)
kernel void myComputeKernel3D(
    texture3d<float, access::write> outputHeightVolume [[texture(0)]],
    texture3d<float3, access::write> outputDerivativeVolume [[texture(1)]],
    uint3 gid [[thread_position_in_grid]], // 3D thread position
    constant float3& scaleFactor [[buffer(0)]],
    constant uint& octaves [[buffer(1)]],
    constant float& lacunarity [[buffer(2)]],
    constant float& persistence [[buffer(3)]]
) {
    // Get texture dimensions
    uint width = outputHeightVolume.get_width();
    uint height = outputHeightVolume.get_height();
    uint depth = outputHeightVolume.get_depth();

    // Normalize grid position to [0.0, 1.0] range
    float3 uvw = float3(gid) / float3(width, height, depth);

    // Scale uvw to a desired coordinate space for the noise
    // Adjust this scale to zoom in/out of your noise pattern
    float3 p = uvw * scaleFactor;

    FBMResult result = fbm(p, octaves, lacunarity, persistence);

    // Output eroded height (e.g., mapped to [0,1] for a texture)
    outputHeightVolume.write(float4((result.height + 1.0) * 0.5), gid);

    // Output derivative of the *eroded* FBM (dx, dy, dz components)
    // Note: For visualization, you might encode these into RGB channels
    outputDerivativeVolume.write(float4(result.derivative, 1.0), gid);
}
*/

#include <metal_stdlib>
using namespace metal;

// Permutation table for repeatable hashing (must be 256 entries)
// This is a common practice for noise functions.
constant uchar P[256] = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,
    37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
    57,177,33,88,237,149,56,87,173,24,65,49,1,167,76,220,166,92,109,9,73,121,50,48,208,
    228,78,136,191,150,146,187,221,68,2,18,60,250,172,100,20,205,74,58,162,55,104,217,
    182,93,184,192,168,206,171,25,161,174,181,85,102,107,119,214,124,116,86,244,147,169,
    128,47,204,236,105,176,22,170,113,108,132,70,242,125,227,157,79,183,59,210,129,249,
    200,82,239,27,111,185,212,193,253,238,175,159,241,54,145,115,139,14,29,19,40,251,
    163,106,80,248,12,66,118,243,3,110,195,64,31,222,235,5,17,141,83,153,188,245,207,
    202,67,101,135,84,152,126,164,196,180,112,165,209,215,123,189,20,81,246,122,226,
    229,143,213,199,16,133,127,171,98,4,130,28,46,61,114,134,224,158,230,244,138,44,
    223,77,20,25,45,20,54,77,20,15,45,25,20 // Additional entries to fill 256 if needed (example, not actual values)
};

// --- Helper Functions for Quintic Curve and its Derivatives ---

// Quintic smoothing curve: 6t^5 - 15t^4 + 10t^3
float quintic(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// First derivative of quintic curve: 30t^4 - 60t^3 + 30t^2
float quinticDerivative(float t) {
    return 30.0 * t * t * (t * t - 2.0 * t + 1.0); // Simplified: 30t^2 * (t-1)^2
}

// Second derivative of quintic curve: 120t^3 - 180t^2 + 60t
float quinticSecondDerivative(float t) {
    return 60.0 * t * (2.0 * t * t - 3.0 * t + 1.0); // Simplified: 60t * (2t-1) * (t-1)
}

// Linear interpolation (lerp) utility
float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

// --- 3D Value Noise Functions (Value, Gradient, Hessian) ---

// Struct to return value, gradient (first derivative), and Hessian (second derivative)
struct NoiseResult {
    float value;
    float3 derivative; // (dN/dx, dN/dy, dN/dz)
    float3x3 hessian;  // The 3x3 Hessian matrix
};

// Hash function for 3D integer coordinates
// Returns a float in [-1.0, 1.0] from a seeded hash of the input coordinates.
float hash3D(int3 p) {
    // Combine coordinates and hash using permutation table
    // A simple approach for demonstrative purposes.
    // In a full implementation, you'd wrap indices for the P table.
    int x_idx = p.x & 255;
    int y_idx = p.y & 255;
    int z_idx = p.z & 255;

    // Use a chain of indices from the permutation table
    // (P[x+P[y+P[z]]]) for repeatable hashing.
    // Example from Perlin/Simplex noise, adapted for value hashing.
    float val = (float)P[ (P[ (P[x_idx] + y_idx) & 255 ] + z_idx) & 255 ];

    return val / 127.5 - 1.0; // Map [0, 255] to [-1.0, 1.0]
}


// Main 3D Value Noise function
NoiseResult noise(float3 p) {
    int3 p0 = int3(floor(p)); // Integer part of coordinates
    float3 f = p - float3(p0); // Fractional part of coordinates

    // Smoothed fractional parts and their derivatives
    float3 s = float3(quintic(f.x), quintic(f.y), quintic(f.z));
    float3 ds = float3(quinticDerivative(f.x), quinticDerivative(f.y), quinticDerivative(f.z));
    float3 dds = float3(quinticSecondDerivative(f.x), quinticSecondDerivative(f.y), quinticSecondDerivative(f.z));

    // Get the 8 corner values from hashing
    float v000 = hash3D(p0 + int3(0,0,0));
    float v100 = hash3D(p0 + int3(1,0,0));
    float v010 = hash3D(p0 + int3(0,1,0));
    float v110 = hash3D(p0 + int3(1,1,0));
    float v001 = hash3D(p0 + int3(0,0,1));
    float v101 = hash3D(p0 + int3(1,0,1));
    float v011 = hash3D(p0 + int3(0,1,1));
    float v111 = hash3D(p0 + int3(1,1,1));

    // --- Calculate Noise Value (Trilinear Interpolation) ---
    float noiseValue = lerp(
        lerp(lerp(v000, v100, s.x), lerp(v010, v110, s.x), s.y),
        lerp(lerp(v001, v101, s.x), lerp(v011, v111, s.x), s.y),
        s.z
    );

    // --- Calculate Gradient (First Derivative) ---
    // Partial derivatives with respect to smoothed coordinates (dSx, dSy, dSz)
    float d_du = lerp(lerp(v100 - v000, v110 - v010, s.y), lerp(v101 - v001, v111 - v011, s.y), s.z);
    float d_dv = lerp(lerp(v010 - v000, v110 - v100, s.x), lerp(v011 - v001, v111 - v101, s.x), s.z);
    float d_dw = lerp(lerp(lerp(v001 - v000, v101 - v100, s.x), lerp(v011 - v010, v111 - v110, s.x), s.y));

    // Chain rule: dN/dx = (dN/dSx) * S'(fx)
    float3 gradient = float3(
        d_du * ds.x,
        d_dv * ds.y,
        d_dw * ds.z
    );

    // --- Calculate Hessian (Second Derivative) ---
    float3x3 hessian = float3x3(0.0);

    // Terms involving d^2N/dx^2, d^2N/dy^2, d^2N/dz^2 (diagonal elements)
    hessian[0][0] = d_du * dds.x; // (dN/dSx) * S''(fx)
    hessian[1][1] = d_dv * dds.y; // (dN/dSy) * S''(fy)
    hessian[2][2] = d_dw * dds.z; // (dN/dSx) * S''(fz)

    // d^2N/dxdy = d/dx [ (dN/dSy) * S'(fy) ]
    // = (d/dSx [dN/dSy]) * S'(fx) * S'(fy) + (dN/dSy) * S''(fy) * 0 (no fx dependence on S'(fy))
    // d/dSx [dN/dSy] = lerp(lerp(v110 - v100, v010 - v000, s.x)) -> (v110-v100) - (v010-v000)
    float d_dudv = lerp(v110 - v010 - v100 + v000, v111 - v011 - v101 + v001, s.z);
    float d_dudw = lerp(lerp(v101 - v001, v111 - v011, s.y) - lerp(v100 - v000, v110 - v010, s.y)); // Difference between dz at u=1 vs u=0
    float d_dvdw = lerp(lerp(v011 - v001, v111 - v101, s.x) - lerp(v010 - v000, v110 - v100, s.x));

    // Off-diagonal terms (mixed partials, e.g., d^2N/dxdy)
    // d^2N/dxdy = (d/dSx [dN/dSy]) * S'(fx) * S'(fy)
    hessian[0][1] = d_dudv * ds.x * ds.y; // d^2N/dxdy
    hessian[1][0] = hessian[0][1];        // Symmetric Hessian

    // d^2N/dxdz = (d/dSx [dN/dSz]) * S'(fx) * S'(fz)
    hessian[0][2] = d_dudw * ds.x * ds.z; // d^2N/dxdz
    hessian[2][0] = hessian[0][2];        // Symmetric Hessian

    // d^2N/dydz = (d/dSy [dN/dSz]) * S'(fy) * S'(fz)
    hessian[1][2] = d_dvdw * ds.y * ds.z; // d^2N/dydz
    hessian[2][1] = hessian[1][2];        // Symmetric Hessian

    return NoiseResult{ .value = noiseValue, .derivative = gradient, .hessian = hessian };
}

/*
// Example of how you might use it in a kernel (conceptual)
kernel void generate3DValueNoise(
    texture3d<float, access::write> outputValueTexture [[texture(0)]],
    texture3d<float3, access::write> outputGradientTexture [[texture(1)]],
    texture3d<float3x3, access::write> outputHessianTexture [[texture(2)]],
    uint3 gid [[thread_position_in_grid]],
    constant float3& scaleFactor [[buffer(0)]]
) {
    uint width = outputValueTexture.get_width();
    uint height = outputValueTexture.get_height();
    uint depth = outputValueTexture.get_depth();

    float3 uvw = float3(gid) / float3(width, height, depth);
    float3 p = uvw * scaleFactor; // Scale for desired noise "zoom"

    NoiseResult result = noise(p);

    // Output value (mapped to [0,1] for texture)
    outputValueTexture.write(float4((result.value + 1.0) * 0.5), gid);

    // Output gradient
    outputGradientTexture.write(float4(result.derivative, 1.0), gid);

    // Output Hessian (e.g., store in a custom format or multiple textures if needed)
    // For simplicity, just showing how you'd access it.
    // outputHessianTexture.write(float4(result.hessian[0][0], result.hessian[0][1], result.hessian[0][2], 0.0), gid);
    // ... etc. (writing float3x3 directly to texture might require special handling)
}
*/

#endif
