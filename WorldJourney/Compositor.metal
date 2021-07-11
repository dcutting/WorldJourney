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
                                     texture2d<float> positionTexture [[texture(2)]],
                                     texture2d<float> waveNormalTexture [[texture(3)]],
                                     texture2d<float> wavePositionTexture [[texture(4)]]) {
  constexpr sampler sample(min_filter::linear, mag_filter::linear);
  float4 albedo = albedoTexture.sample(sample, in.uv);
  float3 terrainNormal = normalize(normalTexture.sample(sample, in.uv).xyz);
  float3 terrainPosition = positionTexture.sample(sample, in.uv).xyz;
  float3 waveNormal = normalize(waveNormalTexture.sample(sample, in.uv).xyz);
  float3 wavePosition = wavePositionTexture.sample(sample, in.uv).xyz;

  // Sky and sun.
  bool is_terrain = albedo.g > 0.5;
  bool is_water = albedo.r > 0.5;

  // Lighting.
  float3 ambientColour = uniforms.ambientColour;
  float3 diffuseColour(0);
  float3 specularColour(0);

  if (is_terrain) {

    // Normal rendering mode.
    if (uniforms.renderMode == 1) {
      return float4((terrainNormal + 1) / 2, 1);
    }
    
    // Realistic rendering mode.
    float3 toLight = normalize(uniforms.sunPosition - terrainPosition);
    float faceness = dot(terrainNormal, toLight);
    
    // Diffuse lighting.
    float attenuation = 1.0;
    float dist = distance(uniforms.cameraPosition, terrainPosition);
    float fog = 3000.0;
    attenuation = 1.0 - (clamp(dist / (fog), 0.0, 0.6));
    float diffuseIntensity = clamp(faceness, 0.0, 1.0);
    diffuseColour = terrain.groundColour * diffuseIntensity;
    diffuseColour.xy *= attenuation;
  
  } else if (is_water) {
    
    // Normal rendering mode.
    if (uniforms.renderMode == 1) {
      return float4((waveNormal + 1) / 2, 1);
    }
    
    // Realistic rendering mode.
    float3 toLight = normalize(uniforms.sunPosition - wavePosition);
    float faceness = dot(waveNormal, toLight);

    // Diffuse lighting.
    float attenuation = 1.0;
    float dist = distance(uniforms.cameraPosition, wavePosition);
    float fog = 3000.0;
    attenuation = 1.0 - (clamp(dist / (fog), 0.0, 0.6));
    float diffuseIntensity = clamp(faceness, 0.0, 1.0);
    float3 water(0, 46.7/256.0, 74.5/256.0);
    diffuseColour = water * diffuseIntensity;
    diffuseColour.xy *= attenuation;

    // Specular lighting.
    float3 reflection = normalize(reflect(-toLight, waveNormal));
    float3 toCamera = normalize(uniforms.cameraPosition - wavePosition);
    float specularIntensity = dot(reflection, toCamera);
    specularIntensity = clamp(specularIntensity, 0.0, 1.0);
    specularIntensity = pow(specularIntensity, terrain.shininess);
    if (specularIntensity > 0.0) {
      float fade = smoothstep(-1.0, 0.0, faceness);
      float specularFade = specularIntensity * fade;
      specularColour = uniforms.sunColour * specularFade;
      diffuseColour = diffuseColour * (1.0 - specularFade);
    }
    
  } else {
    
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

  // Combined lighting.
  float3 lit = ambientColour + diffuseColour + specularColour;
  
  // Gamma correction.
  lit = pow(lit, float3(1.0/2.2));

  return float4(lit, 1);
}
