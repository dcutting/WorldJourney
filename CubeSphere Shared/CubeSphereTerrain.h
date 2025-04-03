#ifndef CubeSphereTerrain_h
#define CubeSphereTerrain_h

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 p, float amplitude, float octaves, float epsilon);
float4 calculateDetail(int3 cubeOrigin, int cubeSize, float2 p, float octaves);

#endif
