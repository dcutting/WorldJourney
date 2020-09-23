#include <metal_stdlib>
using namespace metal;

#include "../Shaders/Common.h"

constexpr sampler repeat_sample(coord::normalized, address::repeat, filter::linear);

float texture_noise_2d(float2 st, texture2d<float> noiseMap) {
    return noiseMap.sample(repeat_sample, st).r;
}

float fbm_texture_noise_2d(float2 st, Fractal fractal, texture2d<float> noiseMap) {
    float value = 0.0;
    float f = fractal.frequency;
    float a = fractal.amplitude;
    for (int i = 0; i < fractal.octaves; i++) {
        value += a * texture_noise_2d(st * f, noiseMap);
        f *= fractal.lacunarity;
        a *= fractal.persistence;
   }
   return value;
}
