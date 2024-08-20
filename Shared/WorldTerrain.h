#ifndef WorldTerrain_h
#define WorldTerrain_h

float4 sampleInf(int3 cubeOrigin, int cubeSize, float3 cubeOffset, float frequency, float amplitude, float octaves);

float2 warp2(float2 p, float f, float2 dx, float2 dy);
float3 warp3(float3 p, float f, float3 dx, float3 dy, float3 dz);

#endif
