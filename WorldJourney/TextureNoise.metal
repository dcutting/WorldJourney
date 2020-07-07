#include <metal_stdlib>
#include "Common.h"
using namespace metal;

constexpr sampler repeat_sample(coord::normalized, address::repeat, filter::linear);

float random(float2 st, texture2d<float> noiseMap) {
    return noiseMap.sample(repeat_sample, st).r;
}

float fbm(float2 st, Fractal fractal, int octaves, texture2d<float> noiseMap) {
    float value = 0.0;
    float f = fractal.frequency;
    float a = fractal.amplitude;
    for (int i = 0; i < octaves; i++) {
        value += a * random(st * f, noiseMap);
        f *= fractal.lacunarity;
        a *= fractal.persistence;
   }
   return value;
}
