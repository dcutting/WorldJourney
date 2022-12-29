#include <metal_stdlib>
#include "Common.h"
using namespace metal;

#include "Noise.h"

constant float E = 2.71828;

// The MIT License
// Copyright © 2017 Inigo Quilez
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


// Computes the analytic derivatives of a 3D Gradient Noise. This can be used for example to compute normals to a
// 3d rocks based on Gradient Noise without approximating the gradient by having to take central differences. More
// info here: http://iquilezles.org/www/articles/gradientnoise/gradientnoise.htm


// Value    Noise 2D, Derivatives: https://www.shadertoy.com/view/4dXBRH
// Gradient Noise 2D, Derivatives: https://www.shadertoy.com/view/XdXBRH
// Value    Noise 3D, Derivatives: https://www.shadertoy.com/view/XsXfRH
// Gradient Noise 3D, Derivatives: https://www.shadertoy.com/view/4dffRH
// Value    Noise 2D             : https://www.shadertoy.com/view/lsf3WH
// Value    Noise 3D             : https://www.shadertoy.com/view/4sfGzS
// Gradient Noise 2D             : https://www.shadertoy.com/view/XdXGW8
// Gradient Noise 3D             : https://www.shadertoy.com/view/Xsl3Dl
// Simplex  Noise 2D             : https://www.shadertoy.com/view/Msf3WH
// Wave     Noise 2D             : https://www.shadertoy.com/view/tldSRj


float2 gHash2(float2 x)  // replace this by something better
{
    const float2 k = float2( 0.3183099, 0.3678794 );
    x = x*k + k.yx;
    return -1.0 + 2.0*fract( 16.0 * k*fract( x.x*x.y*(x.x+x.y)) );
}

float hash2( float2 p )  // replace this by something better
{
    p  = 50.0*fract( p*0.3183099 + float2(0.71,0.113));
    return -1.0+2.0*fract( p.x*p.y*(p.x+p.y) );
}

float3 hash( float3 p ) // replace this by something better. really. do
{
    p = float3( dot(p,float3(127.1,311.7, 74.7)),
              dot(p,float3(269.5,183.3,246.1)),
              dot(p,float3(113.5,271.9,124.6)));

    return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

// return value noise (in x) and its derivatives (in yzw)
float4 simplex_noised_3d(float3 x)
{
    // grid
    float3 i = floor(x);
    float3 w = fract(x);
    
    #if 1
    // quintic interpolant
    float3 u = w*w*w*(w*(w*6.0-15.0)+10.0);
    float3 du = 30.0*w*w*(w*(w-2.0)+1.0);
    #else
    // cubic interpolant
    float3 u = w*w*(3.0-2.0*w);
    float3 du = 6.0*w*(1.0-w);
    #endif
  
    // gradients
    float3 ga = hash( i+float3(0.0,0.0,0.0) );
    float3 gb = hash( i+float3(1.0,0.0,0.0) );
    float3 gc = hash( i+float3(0.0,1.0,0.0) );
    float3 gd = hash( i+float3(1.0,1.0,0.0) );
    float3 ge = hash( i+float3(0.0,0.0,1.0) );
    float3 gf = hash( i+float3(1.0,0.0,1.0) );
    float3 gg = hash( i+float3(0.0,1.0,1.0) );
    float3 gh = hash( i+float3(1.0,1.0,1.0) );
    
    // projections
    float va = dot( ga, w-float3(0.0,0.0,0.0) );
    float vb = dot( gb, w-float3(1.0,0.0,0.0) );
    float vc = dot( gc, w-float3(0.0,1.0,0.0) );
    float vd = dot( gd, w-float3(1.0,1.0,0.0) );
    float ve = dot( ge, w-float3(0.0,0.0,1.0) );
    float vf = dot( gf, w-float3(1.0,0.0,1.0) );
    float vg = dot( gg, w-float3(0.0,1.0,1.0) );
    float vh = dot( gh, w-float3(1.0,1.0,1.0) );
    
    // interpolations
    return float4( va + u.x*(vb-va) + u.y*(vc-va) + u.z*(ve-va) + u.x*u.y*(va-vb-vc+vd) + u.y*u.z*(va-vc-ve+vg) + u.z*u.x*(va-vb-ve+vf) + (-va+vb+vc-vd+ve-vf-vg+vh)*u.x*u.y*u.z,    // value
                 ga + u.x*(gb-ga) + u.y*(gc-ga) + u.z*(ge-ga) + u.x*u.y*(ga-gb-gc+gd) + u.y*u.z*(ga-gc-ge+gg) + u.z*u.x*(ga-gb-ge+gf) + (-ga+gb+gc-gd+ge-gf-gg+gh)*u.x*u.y*u.z +   // derivatives
                 du * (float3(vb,vc,ve) - va + u.yzx*float3(va-vb-vc+vd,va-vc-ve+vg,va-vb-ve+vf) + u.zxy*float3(va-vb-ve+vf,va-vb-vc+vd,va-vc-ve+vg) + u.yzx*u.zxy*(-va+vb+vc-vd+ve-vf-vg+vh) ));
}

float3 gNoised2(float2 p) {
    float2 i = floor( p );
    float2 f = fract( p );

#if 1
    // quintic interpolation
    float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
  float2 du = 30.0*f*f*(f*(f-2.0)+1.0);
#else
    // cubic interpolation
  float2 u = f*f*(3.0-2.0*f);
  float2 du = 6.0*f*(1.0-f);
#endif
    
  float2 ga = gHash2( i + float2(0.0,0.0) );
  float2 gb = gHash2( i + float2(1.0,0.0) );
  float2 gc = gHash2( i + float2(0.0,1.0) );
  float2 gd = gHash2( i + float2(1.0,1.0) );
    
    float va = dot( ga, f - float2(0.0,0.0) );
    float vb = dot( gb, f - float2(1.0,0.0) );
    float vc = dot( gc, f - float2(0.0,1.0) );
    float vd = dot( gd, f - float2(1.0,1.0) );

    return float3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),   // value
                 ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +  // derivatives
                 du * (u.yx*(va-vb-vc+vd) + float2(vb,vc) - va));
}

// return value noise (in x) and its derivatives (in yz)
float3 vNoised2(float2 p )
{
    float2 i = floor( p );
    float2 f = fract( p );
  
#if 1
    // quintic interpolation
    float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    float2 du = 30.0*f*f*(f*(f-2.0)+1.0);
#else
    // cubic interpolation
    float2 u = f*f*(3.0-2.0*f);
    float2 du = 6.0*f*(1.0-f);
#endif
    
    float va = hash2( i + float2(0.0,0.0) );
    float vb = hash2( i + float2(1.0,0.0) );
    float vc = hash2( i + float2(0.0,1.0) );
    float vd = hash2( i + float2(1.0,1.0) );
    
//    float k0 = va;
//    float k1 = vb - va;
//    float k2 = vc - va;
//    float k4 = va - vb - vc + vd;

    return float3( va+(vb-va)*u.x+(vc-va)*u.y+(va-vb-vc+vd)*u.x*u.y, // value
                 du*(u.yx*(va-vb-vc+vd) + float2(vb,vc) - va) );     // derivative
}

constant float3x3 m3( 0.00,  0.80,  0.60,
                      -0.80,  0.36, -0.48,
                      -0.60, -0.48,  0.64 );

constant float2x2 m2( 0.48,  0.80,
                      -0.80,  -0.36);

// https://iquilezles.org/www/articles/morenoise/morenoise.htm
float4 fbmd_7(float3 x, float f, float a, float l, float p, int o) {
  float freq = f;
  float amp = a;
  float lacu = l;
  float pers = p;

  float height = 0.0;
  float3 deriv = float3(0.0);

  float3 next = freq * x;

  for (int i = 0; i < o; i++) {
    float4 noised = simplex_noised_3d(next);
    // + (-2 * deriv)); // TODO: do I need to scale the noise like here: https://github.com/tuxalin/procedural-tileable-shaders/blob/master/noise.glsl
    
    deriv += amp * freq * noised.yzw;
    float nx = noised.x;
//    float billow = abs(nx);
//    float ridge = 1-billow;
//    height += amp * (ridge);// / (1 + dot(deriv, deriv));
    height += amp * nx;
    
    amp *= pers;
    freq *= lacu;

    next = freq * m3 * x;
  }
  
  return float4(height, deriv);
}


float4 fbm(float3 x, int octaves)
{
    float f = 1.98;  // could be 2.0
    float s = 0.49;  // could be 0.5
    float a = 0.0;
    float b = 0.2;
    float3  d = float3(0.0);
    float3x3  m = float3x3(1.0,0.0,0.0,
    0.0,1.0,0.0,
    0.0,0.0,1.0);
    for( int i=0; i < octaves; i++ )
    {
        float4 n = simplex_noised_3d(x);
        a += b*n.x;          // accumulate values
        d += b*m*n.yzw;      // accumulate derivatives
        b *= s;
        x = f*m3*x;
        m = f*m3*m;
    }
    return float4( a, d );
}

float3 sharp_abs(float3 a) {
  float h = abs(a.x);
  float2 d = a.x < 0 ? -a.yz : a.yz;
//  float2 d = mix(-a.yz, a.yz, 1.0/(1+pow(E, 100*-a.x)));  // TODO: seems to be good enough with abs height and smooth deriv.
  return float3(h, d);
}

float3 smooth_abs(float3 a) {
  float h = sqrt(pow(a.x, 2) + 0.00001);
  float2 d = mix(-a.yz, a.yz, 1.0/(1+pow(E, 100*-a.x)));
  return float3(h, d);
}

float3 fbm2(float2 x, float frequency, float amplitude, float lacunarity, float persistence, int octaves, int billow, int ridge)
{
  float height = 0.0;
  float2  derivative = float2(0.0);
  x = frequency * x;
  float2x2  m = float2x2(1.0,0.0,
                         0.0,1.0);
  for( int i=0; i < octaves; i++ )
  {
    float3 n = gNoised2(x);
    float2 dd = amplitude*frequency*n.yz;
    float base = n.x;
    if (billow) {
      float3 c = smooth_abs(float3(base, dd));
      base = c.x;
      dd = c.yz;
      if (ridge) {
        base = amplitude-base;  // TODO: normally this is 1-base but for small amplitudes it makes everything too high.
        dd = -dd;
      }
    }
    height += amplitude*base;          // accumulate values
    derivative += dd;      // accumulate derivatives
    amplitude *= persistence;
    frequency *= lacunarity;
    x = frequency * x;
  }
  return float3( height, derivative );
}



constant float3 randomVectors[] = {
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

struct WaveComponent {
  float Psa;
  float Psb;
  float nsa;
  float3 nsb;
};

WaveComponent addWaves(WaveComponent b, int N, float r, float3 v, float t, int ix,
                       float Ai, float wi, float pi, float Qi,
                       float Aip, float wil, float pii, float Qii) {
  float Psa = b.Psa;
  float Psb = b.Psb;
  float nsa = b.nsa;
  float3 nsb = b.nsb;

  for (int i = 0; i < N; i++) {
    float3 oi = normalize(randomVectors[(i + ix) % 20]);
    float li = acos(dot(v, oi)) * r;
    float3 di = cross(v, cross((v-oi), v));

    Psa += Ai * sin(wi*li + pi*t);
    Psb += dot(Qi * Ai * cos(wi*li + pi*t), di);
    nsa += Qi * Ai * wi * sin(wi*li + pi*t);
    nsb += di * Ai * wi * cos(wi*li + pi*t);

    Ai *= Aip;
    wi *= wil;
    pi *= pii;
    Qi *= Qii;
  }
  
  return {
    .Psa = Psa,
    .Psb = Psb,
    .nsa = nsa,
    .nsb = nsb
  };
}

Gerstner gerstner(float3 x, float r, float t) {
  float3 v = normalize(x);

  // components, N, r, v, t, ix, Ai, wi, pi, Qi, Aip, wil, pii, Qii
  // N = numebr of waves
  // Ai, Aip = amplitude
  // wi, wil = frequency
  // pi, pii = wave speed
  // Qi, Qii = crest sharpness (should never exceed 1)
  WaveComponent b = { 0, 0, 0, float3(0) };
//  b = addWaves(b, 10, r, v, t, 0, 1, 0.02, 0.01, 1, 0.9, 1.1, 1, 1);
  b = addWaves(b, 10, r, v, t, 10, 0.1, 0.2, 0.2, 0.5, 0.9, 1.1, 0.9, 0.95);
//  b = addWaves(b, 5, r, v, t, 20, 0.1, 0.09, 0.1, 1, 0.9, 1.1, 0.9, 0.95);

  float3 Ps = v * r + v * b.Psa + b.Psb;
  float3 ns = v - v * b.nsa - b.nsb;
  
  return {
    .position = Ps,
    .normal = ns
  };
}
