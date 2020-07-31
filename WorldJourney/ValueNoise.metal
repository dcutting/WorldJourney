#include <metal_stdlib>
using namespace metal;

// https://www.iquilezles.org/www/articles/morenoise/morenoise.htm

float iq_hash(float2 p) {
  p = 50.0 * fract(p * 0.3183099 + float2(0.71, 0.113));
  return -1.0 + 2.0 * fract(p.x * p.y * (p.x + p.y));
}

// Return value noise (in x) and its derivatives (in yz).
float3 iq_noise_deriv(float2 x) {
  float2 p = floor(x);
  float2 f = fract(x);
  
#if 0
  // cubic interpolation
  float2 u = f*f*(3.0-2.0*f);
  float2 du = 6.0*f*(1.0-f);
  //    float2 ddu = 6.0 - 12.0*f;
#else
  // quintic interpolation
  float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
  float2 du = 30.0*f*f*(f*(f-2.0)+1.0);
  //    float2 ddu = 60.0*f*(1.0+f*(-3.0+2.0*f));
#endif
  
  float a = iq_hash( p + float2(0.5,0.5) );
  float b = iq_hash( p + float2(1.5,0.5) );
  float c = iq_hash( p + float2(0.5,1.5) );
  float d = iq_hash( p + float2(1.5,1.5) );
  
  //    float k0 = a;
  //    float k1 = b - a;
  //    float k2 = c - a;
  //    float k4 = a - b - c + d;
  
  // value
  float va = a+(b-a)*u.x+(c-a)*u.y+(a-b-c+d)*u.x*u.y;
  // derivative
  float2 de = du*(float2(b-a,c-a)+(a-b-c+d)*u.yx);
  // hessian (second derivartive)
  //    float2x2 he = float2x2(ddu.x*(k1 + k4*u.y),
  //                           du.x*k4*du.y,
  //                           du.y*k4*du.x,
  //                           ddu.y*(k2 + k4*u.x));
  
  return float3(va, de);
}

float3 iq_fbm_deriv(float2 x, float lacunarity, float persistence, int octaves, float scale, float height) {
  float a = 0.0;
  float b = 1.0;
  float f = 1.0;
  float2 d = float2(0.0);
  for (int i = 0; i < octaves; i++) {
    float3 n = iq_noise_deriv(f*x*scale);
    a += b*n.x;           // accumulate values
    d += b*n.yz*f;        // accumulate derivatives (note that in this case b*f=1.0)
    b *= persistence;      // amplitude decrease
    f *= lacunarity;       // frequency increase
  }
  
  a *= height;
  d *= height*scale;
  
  // compute normal based on derivatives
  return float3(a, -d.x, -d.y);
}
