#include <metal_stdlib>

using namespace metal;

#include "Noise.h"
#include "../Shared/InfiniteNoise.h"

/// Hash

constant uint k = 1103515245U;  // GLIB C

float3 iHash33( uint3 x )
{
  x = ((x>>8U)^x.yzx)*k;
  x = ((x>>8U)^x.yzx)*k;
  x = ((x>>8U)^x.yzx)*k;

  return float3(x)*(1.0/float(0xffffffffU));
}

// Pseudo Hash Suite, All 16 Pairs.
// Made by Rik Riesmeijer, 2024 - No rights reserved.
// License: Copyright-Free, (CC0), Citing this source is not required.
// Notice: No QA has been done as of now (sep 2024), user discretion is adviced.

// Convenient helper functions that do salting etc.
uint4 rndU44(uint4 u) { return u.yzwx * u.zwxy ^ u; }
uint4 h44uvc(float4  c) { return uint4(c * 22.33 + 33.33); }
float4  hlpr24(float4  c) { return fract(fract(c) / fract(c.wxyz * c.zwxy + c.yzwx)); }
float4  colc44(float4  c) { return smoothstep(0.4, 0.6, c / 43e8); }
float3  hlpr23(float2  v) { return fract(fract(v *= v.y + 333.3).xyx / fract(v.yxy * v.xxy)); }
float2  h1toh2(float x) { return float2(x / modf(x, x), x / 33e3 + 0.03); }
float4  h3toh4(float3  p) { return float4(p.x * p.y + p.z, p); }
float4  h2toh4(float2  v) { return float4(v / 3.33 + 321.0, v * 1e3 + 333.3); }
float v2tofl(float2  v) { return v.x * (v.y / 12.34 + 56.78); }

// Four dimensional input versions of hashing.
float4  hash44(float4  c) { return colc44(float4(rndU44(rndU44(h44uvc(c))))); }
float3  hash43(float4  c) { return hash44(c).xyz; }
float2  hash42(float4  c) { return hash44(c).yz; }
float hash41(float4  c) { return hash44(c).w; }

// Three dimensional input versions of hashing.
float4  hash34(float3  p) { return hash44(h3toh4(p));}
float3  hash33(float3  p) { return hash43(h3toh4(p));}
float2  hash32(float3  p) { return hash42(h3toh4(p));}
float hash31(float3  p) { return hash41(h3toh4(p));}

uint triple32(uint x)
{
  x ^= x >> 17;
  x *= 0xed5ad4bbU;
  x ^= x >> 11;
  x *= 0xac4c1b51U;
  x ^= x >> 15;
  x *= 0x31848babU;
  x ^= x >> 14;
  return x;
}

float inigoHash31(int3 q)  // replace this by something better
{
  float3 p(q.x, q.y, q.z);
  p  = 50.0*fract( p*0.3183099 + float3(0.71,0.113,0.419));
  float r = -1.0+2.0*fract( p.x*p.y*p.z*(p.x+p.y+p.z) );
  return r;
}

float hoskinsHash13(int3 p)
{
  float3 p3(p.x, p.y, p.z);
  p3  = fract(p3 * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return -1.0 + 2.0*fract((p3.x + p3.y) * p3.z);
}

float3 gHash33( float3 p ) // replace this by something better. really. do
{
  p = float3( dot(p,float3(127.1,311.7, 74.7)),
             dot(p,float3(269.5,183.3,246.1)),
             dot(p,float3(113.5,271.9,124.6)));
  
  return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float hash12(int2 q)
{
  float2 p(q.x, q.y);
  float3 p3  = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(float3 p3)
{
  p3  = fract(p3 * .1031);
  p3 += dot(p3, p3.zyx + 31.32);
  return fract((p3.x + p3.y) * p3.z);
}

uint murmurHash13(uint3 src) {
  const uint M = 0x5bd1e995u;
  uint h = 1190494759u;
  src *= M; src ^= src>>24u; src *= M;
  h *= M; h ^= src.x; h *= M; h ^= src.y; h *= M; h ^= src.z;
  h ^= h>>13u; h *= M; h ^= h>>15u;
  return h;
}

constant uint k2 = 1103515245U;  // GLIB C

float tomohiroHash( int3 x )
{
  //I think the value of x is usually comes from 2D/3D coordinates or time in most of applications.
  //These values are small and continuous.
  //So, multiply large prime value first.
  x*=k2;
  //mix x, y, z values.
  //Without shift operator, x, y and z value become same value.
  x = ((x>>2u)^(x.yzx>>1u)^x.zxy)*k2;
  
  return (float3(x)*(1.0/float(0xffffffffU))).x;
}





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



/// Value noise

float hash2( float2 p )  // replace this by something better
{
  p  = 50.0*fract( p*0.3183099 + float2(0.71,0.113));
  return -1.0+2.0*fract( p.x*p.y*(p.x+p.y) );
}

// return value noise (in x, range -1...1) and its derivatives (in yz)
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

  return float3( va+(vb-va)*u.x+(vc-va)*u.y+(va-vb-vc+vd)*u.x*u.y, // value
                du*(u.yx*(va-vb-vc+vd) + float2(vb,vc) - va) );     // derivative
}

#define VNOISED2HASH hash12

float3 vNoised2(int2 grid, float2 f)
{
  int2 i = grid;

#if 1
  // quintic interpolation
  float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
  float2 du = 30.0*f*f*(f*(f-2.0)+1.0);
#else
  // cubic interpolation
  float2 u = f*f*(3.0-2.0*f);
  float2 du = 6.0*f*(1.0-f);
#endif

  float va = VNOISED2HASH( i + int2(0,0) );
  float vb = VNOISED2HASH( i + int2(1,0) );
  float vc = VNOISED2HASH( i + int2(0,1) );
  float vd = VNOISED2HASH( i + int2(1,1) );

  return float3( va+(vb-va)*u.x+(vc-va)*u.y+(va-vb-vc+vd)*u.x*u.y, // value
                du*(u.yx*(va-vb-vc+vd) + float2(vb,vc) - va) );     // derivative
}

uint lowbias32(uint x) {
  x = (x ^ (x >> 16)) * 0x21f0aaadU;
  x = (x ^ (x >> 15)) * 0x735a2d97U;
  return x ^ (x >> 15);
}

uint lowbias32(uint2 x) {
  return lowbias32(x.x ^ lowbias32(x.y));
}  // for 2D input

uint lowbias32(uint3 x) {
  return lowbias32(x.x ^ lowbias32(x.yz));
} // for 3D input

float u2f(uint x) {
  return float(x >> 8U) * as_type<float>(0x33800000U);
}

float f2nf(float x) {
  return x * 2.0 - 1.0;
}

#define VNOISED3HASH(x) (u2f(lowbias32(x)))

constant float TAU = 6.283185307179586;

float3 grad(uint3 x) { // ivec3 lattice to random 3D unit vector (sphere point)
    uint h0 = lowbias32(uint3(x));
    uint h1 = lowbias32(h0);
    // use the first random for the polar angle (latitude)
    float c = 2.0*u2f(h0) - 1.0, // c = cos(theta) = cos(acos(2x-1)) = 2x-1
          s = sqrt(1.0 - c*c);   // s = sin(theta) = sin(acos(c)) = sqrt(1-c*c)
    float phi = TAU * u2f(h1);   // use the 2nd random for the azimuth (longitude)
    return float3(cos(phi) * s, sin(phi) * s, c);
}

float3 naiveGrad(uint3 x) {
  return float3(f2nf(u2f(lowbias32(x.xyz))), f2nf(u2f(lowbias32(x.yzx))), f2nf(u2f(lowbias32(x.zxy))));
}

#define GNOISED3HASH(x) (naiveGrad(x))

// return value noise (in x) and its derivatives (in yzw)
float4 vNoised3(int3 grid, float3 w) {
  int3 i = grid;

  // quintic interpolation
  float3 u = w*w*w*(w*(w*6.0-15.0)+10.0);
  float3 du = 30.0*w*w*(w*(w-2.0)+1.0);

  float a = VNOISED3HASH(uint3(i+int3(0,0,0)));
  float b = VNOISED3HASH(uint3(i+int3(1,0,0)));
  float c = VNOISED3HASH(uint3(i+int3(0,1,0)));
  float d = VNOISED3HASH(uint3(i+int3(1,1,0)));
  float e = VNOISED3HASH(uint3(i+int3(0,0,1)));
  float f = VNOISED3HASH(uint3(i+int3(1,0,1)));
  float g = VNOISED3HASH(uint3(i+int3(0,1,1)));
  float h = VNOISED3HASH(uint3(i+int3(1,1,1)));

  float k0 =   a;
  float k1 =   b - a;
  float k2 =   c - a;
  float k3 =   e - a;
  float k4 =   a - b - c + d;
  float k5 =   a - c - e + g;
  float k6 =   a - b - e + f;
  float k7 = - a + b + c - d + e - f - g + h;

  return float4( k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z,
                du * float3( k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                            k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                            k3 + k6*u.x + k5*u.y + k7*u.x*u.y ) );
}

float4 gNoised3(int3 p, float3 w) {
  // quintic interpolant
  float3 u = w*w*w*(w*(w*6.0-15.0)+10.0);
  float3 du = 30.0*w*w*(w*(w-2.0)+1.0);

  // gradients
  float3 ga = GNOISED3HASH(uint3(p+int3(0,0,0)));
  float3 gb = GNOISED3HASH(uint3(p+int3(1,0,0)));
  float3 gc = GNOISED3HASH(uint3(p+int3(0,1,0)));
  float3 gd = GNOISED3HASH(uint3(p+int3(1,1,0)));
  float3 ge = GNOISED3HASH(uint3(p+int3(0,0,1)));
  float3 gf = GNOISED3HASH(uint3(p+int3(1,0,1)));
  float3 gg = GNOISED3HASH(uint3(p+int3(0,1,1)));
  float3 gh = GNOISED3HASH(uint3(p+int3(1,1,1)));

  // projections
  float va = dot( ga, w-float3(0.0,0.0,0.0) );
  float vb = dot( gb, w-float3(1.0,0.0,0.0) );
  float vc = dot( gc, w-float3(0.0,1.0,0.0) );
  float vd = dot( gd, w-float3(1.0,1.0,0.0) );
  float ve = dot( ge, w-float3(0.0,0.0,1.0) );
  float vf = dot( gf, w-float3(1.0,0.0,1.0) );
  float vg = dot( gg, w-float3(0.0,1.0,1.0) );
  float vh = dot( gh, w-float3(1.0,1.0,1.0) );

  // interpolation
  float v = va +
  u.x*(vb-va) +
  u.y*(vc-va) +
  u.z*(ve-va) +
  u.x*u.y*(va-vb-vc+vd) +
  u.y*u.z*(va-vc-ve+vg) +
  u.z*u.x*(va-vb-ve+vf) +
  u.x*u.y*u.z*(-va+vb+vc-vd+ve-vf-vg+vh);

  float3 d = ga +
  u.x*(gb-ga) +
  u.y*(gc-ga) +
  u.z*(ge-ga) +
  u.x*u.y*(ga-gb-gc+gd) +
  u.y*u.z*(ga-gc-ge+gg) +
  u.z*u.x*(ga-gb-ge+gf) +
  u.x*u.y*u.z*(-ga+gb+gc-gd+ge-gf-gg+gh) +

  du * (float3(vb-va,vc-va,ve-va) +
        u.yzx*float3(va-vb-vc+vd,va-vc-ve+vg,va-vb-ve+vf) +
        u.zxy*float3(va-vb-ve+vf,va-vb-vc+vd,va-vc-ve+vg) +
        u.yzx*u.zxy*(-va+vb+vc-vd+ve-vf-vg+vh) );

  return float4( v, d );
}




/// FBM

constant float E = 2.71828;

constant float2x2 m2(  0.6, -0.8,
                     0.8,  0.6 );
constant float2x2 m2i( 0.6,  0.8,
                      -0.8,  0.6 );
constant float3x3 m3( 0.00,  0.80,  0.60,
                     -0.80,  0.36, -0.48,
                     -0.60, -0.48,  0.64 );


float3 sharp_abs(float3 a) {
  float h = abs(a.x);
  float2 d = a.x < 0 ? -a.yz : a.yz;
  return float3(h, d);
}

float3 smooth_abs(float3 a, float k) {
  float h = sqrt(pow(a.x, 2) + k);
  float2 d = mix(-a.yz, a.yz, saturate(1.0 / (1.0 + pow(E, 10.0*-(a.x + k)))));  // todo: this constant is probably not right.
  return float3(h, d);
}

float3 makeBillowFromBasic(float3 basic, float k) {
  //  return smooth_abs(basic, k);
  return sharp_abs(basic);
}

float3 makeRidgeFromBillow(float3 billow) {
  return float3(1 - billow.x, -billow.yz);
}

// sharpness -1..+1, -1 is bubbly, +1 is sharp
// slopeErosionFactor 0..1, how smooth the steep hills are
// octaveMix 0..1, how much to mix/average out the last two octaves
float3 fbm2(float2 t0, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeErosionFactor)
{
  float height = 0;
  float2 derivative = float2(0);
  float heightP = 0;
  float2 derivativeP = float2(0);
  float2 slopeErosionDerivative = float2(0.0);
  float2 slopeErosionGradient = 0;
  float2x2 m(1, 0,
             0, 1);
  float2 x = frequency * m2 * t0.xy;
  m = frequency * m2i * m;
  for (int i = 0; i < octaves; i++) {
    float3 basic = vNoised2(x);
    basic.yz = m * basic.yz;
    float3 combined;
    float3 billow = makeBillowFromBasic(basic, 0.01); // todo: k should probably be based upon the octave.
    if (sharpness <= 0) {
      combined = mix(basic, billow, abs(sharpness));
    } else {
      float3 ridge = makeRidgeFromBillow(billow);
      combined = mix(basic, ridge, sharpness);
    }
    combined *= amplitude;
    heightP = height;
    derivativeP = derivative;
    height += combined.x;       // accumulate values
    derivative += combined.yz;  // accumulate derivatives
    float altitudeErosion = persistence;  // todo: add concavity erosion.
    slopeErosionDerivative += basic.yz;
    slopeErosionGradient += slopeErosionDerivative * slopeErosionFactor;
    float slopeErosion = 1.0 / (1.0 + dot(slopeErosionGradient, slopeErosionGradient));
    amplitude *= altitudeErosion * slopeErosion;
    x = lacunarity * m2 * x;
    m = lacunarity * m2i * m;
  }
  // todo: rescale to -amplitude...amplitude?
  return mix(float3(heightP, derivativeP), float3(height, derivative), octaveMix);
}















/// OLD.

/*
// From Elevated
float terrainH(float2 x) {
  float persistence = 0.5;
  float lacunarity = 2.0;
  float height = 0.0;
  float2 derivative = float2(0.0);
  float amplitude = 1.0;
  float2 p = x * 0.003 / SC;
  for (int i = 0; i < 16; i++) {
    float4 noise = 0;//vNoised3(p);
    derivative += noise.yz;
    height += amplitude * noise.x / (1.0 + dot(derivative, derivative));
    amplitude *= persistence;
    p = m2 * p * lacunarity;
  }
  return SC*120.0*height;
}
*/

/// Gradient noise

float3 gHash3( float3 p ) // replace this by something better. really. do
{
  p = float3( dot(p,float3(127.1,311.7, 74.7)),
             dot(p,float3(269.5,183.3,246.1)),
             dot(p,float3(113.5,271.9,124.6)));

  return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float2 gHash2(float2 x)  // replace this by something better
{   return gHash3(float3(x,0)).xy;
  const float2 k = float2( 0.3183099, 0.3678794 );
  x = x*k + k.yx;
  return -1.0 + 2.0*fract( 16.0 * k*fract( x.x*x.y*(x.x+x.y)) );
}

// Note this does not fill range -1...1, presumably because of the va dot products.
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
  float3 ga = gHash33( i+float3(0.0,0.0,0.0) );
  float3 gb = gHash33( i+float3(1.0,0.0,0.0) );
  float3 gc = gHash33( i+float3(0.0,1.0,0.0) );
  float3 gd = gHash33( i+float3(1.0,1.0,0.0) );
  float3 ge = gHash33( i+float3(0.0,0.0,1.0) );
  float3 gf = gHash33( i+float3(1.0,0.0,1.0) );
  float3 gg = gHash33( i+float3(0.0,1.0,1.0) );
  float3 gh = gHash33( i+float3(1.0,1.0,1.0) );

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

// https://iquilezles.org/www/articles/morenoise/morenoise.htm
float4 fbmd_7(float3 x, float f, float a, float l, float p, float o) {
  float freq = f;
  float amp = a;
  float lacu = l;
  float pers = p;

  float previousHeight = 0.0;
  float height = 0.0;
  float3 previousDeriv = float3(0.0);
  float3 deriv = float3(0.0);

  float3 next = freq * x;

  for (int i = 0; i < ceil(o); i++) {
    previousHeight = height;
    previousDeriv = deriv;

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

  height = mix(previousHeight, height, fract(o));
  deriv = mix(previousDeriv, deriv, fract(o));

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



float4 sharp_abs3(float4 a) {
  float h = abs(a.x);
  float3 d = a.x < 0 ? -a.yzw : a.yzw;
  return float4(h, d);
}

float4 smooth_abs3(float4 a, float k) {
  float h = sqrt(pow(a.x, 2) + k);
  float3 d = mix(-a.yzw, a.yzw, saturate(1.0 / (1.0 + pow(E, 10.0*-(a.x + k)))));  // todo: this constant is probably not right.
  return float4(h, d);
}

float4 makeBillowFromBasic3(float4 basic, float k) {
  //  return smooth_abs(basic, k);
  return sharp_abs3(basic);
}

float4 makeRidgeFromBillow3(float4 billow) {
  return float4(1 - billow.x, -billow.yzw);
}



// sharpness -1..+1, -1 is bubbly, +1 is sharp
// slopeErosionFactor 0..1, how smooth the steep hills are
// octaveMix 0..1, how much to mix/average out the last two octaves
float4 fbm3(float3 t0, float frequency, float amplitude, float lacunarity, float persistence, int octaves, float octaveMix, float sharpness, float slopeErosionFactor)
{
  float height = 0;
  float3 derivative = float3(0);
  float heightP = 0;
  float3 derivativeP = float3(0);
  float3 slopeErosionDerivative = float3(0.0);
  float3 slopeErosionGradient = 0;
  float3x3 m(1, 0, 0,
             0, 1, 0,
             0, 0, 1);
  float3 x = frequency * m3 * t0.xyz;
  m = frequency * m3 * m;
  for (int i = 0; i < octaves; i++) {
    float4 basic = simplex_noised_3d(x);
    basic.yzw = m * basic.yzw;
    float4 combined;
    float4 billow = makeBillowFromBasic3(basic, 0.01); // todo: k should probably be based upon the octave.
    if (sharpness <= 0) {
      combined = mix(basic, billow, abs(sharpness));
    } else {
      float4 ridge = makeRidgeFromBillow3(billow);
      combined = mix(basic, ridge, sharpness);
    }
    combined *= amplitude;
    heightP = height;
    derivativeP = derivative;
    height += combined.x;       // accumulate values
    derivative += combined.yzw;  // accumulate derivatives
    float altitudeErosion = persistence;  // todo: add concavity erosion.
    slopeErosionDerivative += basic.yzw;
    slopeErosionGradient += slopeErosionDerivative * slopeErosionFactor;
    float slopeErosion = 1.0 / (1.0 + dot(slopeErosionGradient, slopeErosionGradient));
    amplitude *= altitudeErosion * slopeErosion;
    x = lacunarity * m3 * x;
    m = lacunarity * m3 * m;
  }
  // todo: rescale to -amplitude...amplitude?
  return mix(float4(heightP, derivativeP), float4(height, derivative), octaveMix);
}
