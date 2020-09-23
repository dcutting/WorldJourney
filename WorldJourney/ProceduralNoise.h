#ifndef ValueNoise_h
#define ValueNoise_h

float iq_hash(float2 p);
float3 iq_fbm_deriv(float2 x, int octaves);

float4 simplex_3d(float3 x);

#endif /* ValueNoise_h */
