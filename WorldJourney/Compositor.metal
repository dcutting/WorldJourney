#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"

using namespace metal;

struct CompositionOut {
  float4 position [[position]];
  float2 uv;
};



/** composition vertex shader */

vertex CompositionOut composition_vertex(constant float2 *vertices [[buffer(0)]],
                                         constant float2 *uv [[buffer(1)]],
                                         uint id [[vertex_id]]) {
  return {
    .position = float4(vertices[id], 0.0, 1.0),
    .uv = uv[id]
  };
}



/** composition fragment shader */

fragment float4 composition_fragment(CompositionOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> albedoTexture [[texture(0)]],
                                     texture2d<float> normalTexture [[texture(1)]],
                                     texture2d<float> positionTexture [[texture(2)]]) {
  constexpr sampler sample(min_filter::linear, mag_filter::linear);
  float4 albedo = albedoTexture.sample(sample, in.uv);
  float3 normal = normalize(normalTexture.sample(sample, in.uv).xyz);
  float4 position = positionTexture.sample(sample, in.uv);

  // Sky and sun.
  bool is_terrain = albedo.g > 0.5;
  if (!is_terrain) {
    float4 sunScreen4 = (uniforms.projectionMatrix * uniforms.viewMatrix * float4(uniforms.sunPosition, 1));
    float2 sunScreen = float2(sunScreen4.x, -sunScreen4.y) / sunScreen4.w;
    sunScreen = sunScreen / 2.0 + 0.5;
    sunScreen = float2(sunScreen.x * uniforms.screenWidth, sunScreen.y * uniforms.screenHeight);
    float2 uv(in.uv.x * uniforms.screenWidth, in.uv.y * uniforms.screenHeight);
    float sun = 1 - distance(uv / uniforms.screenHeight, sunScreen / uniforms.screenHeight);
    if (sunScreen4.w < 0) { sun = 0.0; }
    sun = pow(sun, 6);
    sun = clamp(sun, 0.0, 1.0);
    float3 lit = terrain.skyColour + uniforms.sunColour * sun;
    return float4(lit, sun);
  }
  
  // Normal rendering mode.
  if (uniforms.renderMode == 1) {
    return float4((normal + 1) / 2, 1);
  }

  // Realistic rendering mode.
  float height = length(position.xyz) - terrain.sphereRadius;
  float3 toSun = normalize(uniforms.sunPosition - position.xyz);
  float3 sphereNormal = normalize(position).xyz;
  float flatness = dot(normal, sphereNormal);
  
  // Diffuse lighting.
  float3 snow(0.85);
  float diffuseIntensity = max(dot(normal, toSun), 0.0);
  float stepped = smoothstep(0.999, 0.9999, flatness);
  float3 diffuseColour = mix(terrain.groundColour, snow, stepped);
  float attenuation = pow(height / terrain.fractal.amplitude, 1.5);
  float3 diffuse = diffuseColour * diffuseIntensity * attenuation;

  // Specular lighting.
  float3 specular = 0;
  // TODO: sometimes see specular highlights on dark side of planet.
  if (terrain.shininess > 0 && diffuseIntensity > 0) {
    float3 reflection = reflect(-toSun, normal);
    float3 toEye = normalize(uniforms.cameraPosition - position.xyz);
    float specularIntensity = pow(max(dot(reflection, toEye), 0.0), terrain.shininess);
    specular = uniforms.sunColour * specularIntensity;
  }

  // Combined lighting.
  float3 lit = uniforms.ambientColour + (diffuse + specular);
  lit = pow(lit, float3(1.0/2.2));
  return float4(lit, 1);
}
