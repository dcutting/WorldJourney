#include <metal_stdlib>
using namespace metal;

// https://www.iquilezles.org/www/articles/morenoise/morenoise.htm

float iq_hash(float2 p) {
    p = 50.0 * fract(p * 0.3183099 + float2(0.71, 0.113));
    return -1.0 + 2.0 * fract(p.x * p.y * (p.x + p.y));
}

// Return value noise (in x) and its derivatives (in yz).
float3 iq_noise_deriv(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    
#if 0
    // quintic interpolation
    float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    float2 du = 30.0*f*f*(f*(f-2.0)+1.0);
#else
    // cubic interpolation
    float2 u = f*f*(3.0-2.0*f);
    float2 du = 6.0*f*(1.0-f);
#endif
    
    float va = iq_hash( i + float2(0.0,0.0) );
    float vb = iq_hash( i + float2(1.0,0.0) );
    float vc = iq_hash( i + float2(0.0,1.0) );
    float vd = iq_hash( i + float2(1.0,1.0) );
    
    return float3( va+(vb-va)*u.x+(vc-va)*u.y+(va-vb-vc+vd)*u.x*u.y, // value
                  du*(u.yx*(va-vb-vc+vd) + float2(vb,vc) - va) );    // derivative
}

float3 iq_fbm_deriv(float2 x, int octaves) {
    float lacunarity = 1.98;  // could be 2.0
    float persistence = 0.49;  // could be 0.5
    float total = 0.0;
    float2 derivs = float2(0.0);
    float f = 4;
    float a = 40;
    
    for (int i = 0; i < octaves; i++) {
        float3 n = iq_noise_deriv(f*x);
        total += a*n.x;        // accumulate values
        derivs += a*n.yz;      // accumulate derivatives
        f *= lacunarity;
        a *= persistence;
    }
    return float3(total, derivs);
}
