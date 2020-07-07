#ifndef TextureNoise_h
#define TextureNoise_h

float random(float2 st, texture2d<float> noiseMap);
float fbm(float2 st, Fractal fractal, int octaves, texture2d<float> noiseMap);

#endif /* TextureNoise_h */
