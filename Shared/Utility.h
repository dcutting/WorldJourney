#ifndef Utility_h
#define Utility_h

float3 applyFog(float3  rgb,      // original color of the pixel
                float distance,   // camera to point distance
                float3  rayDir,   // camera to point vector
                float3  sunDir );  // sun light direction
float3 gammaCorrect(float3 colour);
float3 rgb(int r, int g, int b);

#endif
