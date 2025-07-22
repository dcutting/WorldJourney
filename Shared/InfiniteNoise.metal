#include <metal_stdlib>

#include "../Shared/Noise.h"

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

struct GridPosition {
  int3 i;
  float3 f;
};

GridPosition makeGridPosition(float3 a) {
  return { (int3)floor(a), fract(a) };
}

GridPosition addGridPosition(GridPosition a, GridPosition b) {
  GridPosition r;
  float3 f = a.f + b.f;
  r.i = a.i + b.i + (int3)floor(f);
  r.f = fract(f);
  return r;
}

GridPosition multiplyGridPosition(GridPosition a, float m) {
  GridPosition r;
  // E.g., 3.8 * 2.4 = 9.12
  float3 im = (float3)a.i * m;  // 3 * 2.4 = 7.2
  float3 fm = a.f * m; // 1.92
  float3 ifm = fract(im) + fract(fm); // 0.2 + 0.92 = 1.12
  r.i = (int3)floor(im) + (int3)floor(fm) + (int3)floor(ifm); // 7 + 1 + 1 = 9
  r.f = fract(ifm); // 0.12
  return r;
}

GridPosition rotateGridPosition(GridPosition a, float theta) {
  float ct = cos(theta);
  float st = sin(theta);

  float xi = (float)a.i.x;
  float zi = (float)a.i.z;
  float xit = xi * ct - zi * st;
  float zit = xi * st + zi * ct;
  int3 it = int3(xit, 0, zit);
  GridPosition i = { it, 0 };

  float xf = a.f.x;
  float zf = a.f.z;
  float xft = xf * ct - zf * st;
  float zft = xf * st + zf * ct;
  float3 ft = float3(xft, 0, zft);

  GridPosition f = makeGridPosition(ft);

  return addGridPosition(i, f);
}

float4 jordanTurbulence(GridPosition p, int octaves, float lacunarity = 2.0,
                       float gain1 = 0.8, float gain = 0.5,
                       float warp0 = 0.4, float warp = 0.35,
                       float damp0 = 1.0, float damp = 0.8,
                       float damp_scale = 1.0)
{
    float4 n = vNoised3(p.i, p.f);
    float4 n2 = n * n.x;
  float3 d = n2.yzw;
    float sum = n2.x;
    float2 dsum_warp = warp0*n2.yz;
    float2 dsum_damp = damp0*n2.yz;

    float amp = gain1;
    float freq = lacunarity;
    float damped_amp = amp * gain;

    for(int i=1; i < octaves; i++)
    {
      GridPosition j = addGridPosition(multiplyGridPosition(p, freq), makeGridPosition(float3(dsum_warp.x, 0, dsum_warp.y)));
        n = vNoised3(j.i, j.f);
        n2 = n * n.x;
      d += n2.yzw;
        sum += damped_amp * n2.x;
        dsum_warp += warp * n2.yz;
        dsum_damp += damp * n2.yz;
        freq *= lacunarity;
        amp *= gain;
        damped_amp = amp * (1-damp_scale/(1+dot(dsum_damp,dsum_damp)));
    }
  return float4(sum, d);
}

float4 fbmGP3(GridPosition initial, float frequency, float octaves) {
//  float lacunarity = 2;
//  float gain = 0.5;
//  float amplitude = 1;
//
//  float height = 0;
//  float3 derivative = 0;

  GridPosition p = multiplyGridPosition(initial, frequency);

  return jordanTurbulence(p, octaves);

//  for (int i = 0; i < ceil(octaves); i++) {
//    float4 noise = vNoised3(p.i, p.f);
//
//    height += amplitude * noise.x;
//    derivative += amplitude * frequency * noise.yzw;
//
//    amplitude *= gain;
//    frequency *= lacunarity;
//
//    p = multiplyGridPosition(p, lacunarity);
//  }
//
//  return float4(height, derivative);
}

#ifdef WARPED

float4 fbmInf3(int3 cubeOrigin, int cubeSize, float3 x, float frequency, float amplitude, float octaves, float sharpness, float epsilon) {
  GridPosition origin = { cubeOrigin, 0 };
  GridPosition offset = makeGridPosition(x * cubeSize);
  GridPosition initial = addGridPosition(origin, offset);

  GridPosition p = initial;

  GridPosition p1 = makeGridPosition(float3(3.1, 0, 4.3));
  GridPosition p2 = makeGridPosition(float3(1.2, 0, 0.7));

  float qx = fbmGP3(addGridPosition(p, p1), 0.01, 4, 4).x;
  float qz = fbmGP3(addGridPosition(p, p2), 0.01, 4, 4).x;

  GridPosition q = makeGridPosition(float3(qx, 0, qz));

  GridPosition q1 = makeGridPosition(float3(1.7, 0, 9.2));
  GridPosition q2 = makeGridPosition(float3(8.3, 0, 2.8));

  float rx = fbmGP3(addGridPosition(p, addGridPosition(q1, multiplyGridPosition(q, 8))), 0.001, 4, 4).x;
  float rz = fbmGP3(addGridPosition(p, addGridPosition(q2, multiplyGridPosition(q, 8))), 0.001, 4, 4).x;

  GridPosition r = makeGridPosition(float3(rx, 0, rz));

  GridPosition z = addGridPosition(p, multiplyGridPosition(r, 20));

  return fbmGP3(z, frequency, amplitude, octaves);
}

#else

float4 fbmInf3(int3 cubeOrigin, int cubeSize, float3 x, float frequency, float amplitude, float octaves, float sharpness, float epsilon) {
  GridPosition origin = { cubeOrigin, 0 };
  GridPosition offset = makeGridPosition(x * cubeSize);
  GridPosition initial = addGridPosition(origin, offset);
  return fbmGP3(initial, frequency, octaves);
}

#endif
