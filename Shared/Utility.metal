#include <metal_stdlib>
#include "Utility.h"

using namespace metal;

float3 applyFog(float3  rgb,      // original color of the pixel
                float distance,   // camera to point distance
                float3  rayDir,   // camera to point vector
                float3  sunDir )  // sun light direction
{
  float b = 0.0000005;
  float fogAmount = 1.0 - exp( -distance*b );
  float sunAmount = max( dot( rayDir, sunDir ), 0.0 );
  float3  fogColor  = mix( float3(0.5,0.6,0.7), //float3(0.5,0.6,0.7), // bluish
                          float3(1.0,0.9,0.7), //float3(1.0,0.9,0.7), // yellowish
                          pow(sunAmount,8.0) );
  return mix( rgb, fogColor, fogAmount );
}

float3 gammaCorrect(float3 colour) {
  return pow(colour, float3(1.0/2.2));
}

float3 rgb(int r, int g, int b) {
  return float3((float)r/255.0, (float)g/255.0, (float)b/255.0);
}
