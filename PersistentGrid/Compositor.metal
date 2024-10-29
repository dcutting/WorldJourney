#include <metal_stdlib>
#include "Common.h"
#include "../Shared/Terrain.h"

using namespace metal;

constant float3 SEA_BASE = float3(0.1,0.19,0.22);
constant float3 SEA_WATER_COLOR = float3(0.8,0.9,0.8);
constant float SEA_HEIGHT = 5250;
constant float PI = 3.14159;

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

float diffuse(float3 n,float3 l,float p) {
  return pow(dot(n,l) * 0.4 + 0.6,p);
}

float specular(float3 n,float3 l,float3 e,float s) {
  float nrm = (s + 8.0) / (PI * 8.0);
  return pow(max(dot(reflect(e,n),l),0.0),s) * nrm;
}

// TODO: doesn't account for sphere.
//float3 getSkyColor(float3 e) {
//  e.y = max(e.y,0.0);
//  return float3(pow(1.0-e.y,2.0), 1.0-e.y, 0.6+(1.0-e.y)*0.4);
//}

float3 getSkyColor(float3 e) {
  return float3(0.02, 0.04, 0.05);
}

//float3 getSkyColor(float3 e, float3 l) {
//  e.y = max(e.y,0.0);
//  float h = (dot(e, l) + 1.0) / 2.0;
//  if (h < 0.0) { return float3(0); }
//  float3 sun = float3(pow(1.0-h,2.0), 1.0-h, 0.6+(1.0-h)*0.4);
//  float h = length(e) / 10000
//  float3 sky = float3(0.001, 0.003, 0.002);
//  return mix(sun, sky, 1-h);
//}

float3 getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist, Uniforms uniforms, float3 seaColour) {
  float fresnel = clamp(1.0 - dot(n,-eye), 0.0, 1.0);
  fresnel = pow(fresnel,3.0) * 0.65;
  
//  float3 reflected = uniforms.sunColour * dot(reflect(eye,n), l);
  float3 reflected = getSkyColor(reflect(eye,n));
  float3 refracted = clamp(dot(n,l), 0.0, 1.0) * (seaColour);
//  float3 reflected = getSkyColor(reflect(eye,n));
//  float3 refracted = SEA_BASE + diffuse(n,l,80.0) * SEA_WATER_COLOR * 0.12;

  float3 color = mix(refracted,reflected,fresnel);
  
  float atten = max(1.0 - dot(dist,dist) * 0.001, 0.0);
  color += SEA_WATER_COLOR * (length(p) - SEA_HEIGHT) * 0.18 * atten;
  
  color += float3(specular(n,l,eye,60.0));
  
  return color;
}

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
  bool is_terrain = albedo.g > 0.99 && albedo.a < 0.01;
  bool is_water = albedo.r > 0.99 && albedo.a < 0.01;
  bool is_object = albedo.a > 0.9;

  if (!is_terrain && !is_water && !is_object) {
    
    float4 sunScreen4 = (uniforms.projectionMatrix * uniforms.viewMatrix * float4(uniforms.sunPosition, 1));
    float2 sunScreen = float2(sunScreen4.x, -sunScreen4.y) / sunScreen4.w;
    sunScreen = sunScreen / 2.0 + 0.5;
    sunScreen = float2(sunScreen.x * uniforms.screenWidth, sunScreen.y * uniforms.screenHeight);
    float2 uv(in.uv.x * uniforms.screenWidth, in.uv.y * uniforms.screenHeight);
    float sun = 1 - distance(uv / uniforms.screenHeight, sunScreen / uniforms.screenHeight);
    if (sunScreen4.w < 0) { sun = 0.0; }
    sun = pow(sun, 3);
    sun = clamp(sun, 0.0, 1.0);
    float3 lit = terrain.skyColour + uniforms.sunColour * sun;
    return float4(lit, sun);
    
  }
  
  // Lighting.
  float3 ambientColour = uniforms.ambientColour;

  float3 lit = ambientColour;
  
  if (is_terrain || is_object) {

    float3 sphereNormal = normalize(terrainPosition);
    float flatness = dot(terrainNormal, sphereNormal);

    // Normal rendering mode.
    if (uniforms.renderMode == 1) {
      return float4((terrainNormal + 1) / 2, 1);
    } else if (uniforms.renderMode == 2) {
      return float4(flatness);
    }
    
    // Realistic rendering mode.
    float3 toLight = normalize(uniforms.sunPosition - terrainPosition);
    float faceness = dot(terrainNormal, toLight);
    
    // Diffuse lighting.
    float attenuation = 1.0;
    float dist = distance(uniforms.cameraPosition, terrainPosition);
    float fog = 3000.0;
    attenuation = 1.0 - (clamp(dist / (fog), 0.0, 0.3));
    float diffuseIntensity = clamp(faceness, 0.0, 1.0);

    float3 ground = is_object ? albedo.rgb : terrain.groundColour;

//    if (!is_water) {
//      float3 snow = float3(0.9);
//      float kind = smoothstep(0.9, 0.99, pow(flatness, 2));
//      ground = mix(ground, snow, kind);
//    }
    float3 diffuseColour = ground * diffuseIntensity;
    diffuseColour.xy *= attenuation;
  
    // Combined lighting.
    lit = ambientColour + diffuseColour;
  }
  
  if (is_water) {
    
    // Normal rendering mode.
    if (uniforms.renderMode == 1) {
      return float4((waveNormal + 1) / 2, 1);
    }

#if 1
    float3 p = wavePosition;
    float3 n = waveNormal;
    float3 light = normalize(uniforms.sunPosition - wavePosition);
    float3 dir = normalize(wavePosition - uniforms.cameraPosition);
    float3 dist = wavePosition - uniforms.cameraPosition;
    float3 seaBase = SEA_BASE + SEA_WATER_COLOR;
    float3 background = is_terrain ? mix(seaBase, lit, 0.8) : seaBase;
    float3 sea = getSeaColor(p, n, light, dir, dist, uniforms, background);
    lit = sea;
    
//    if (is_terrain) {
//      lit = ambientColour + mix(lit, sea, 0.9);
//    } else {
//      // TODO: include skybox?
//      lit = ambientColour + sea;
//    }

#else
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
    float3 waterDiffuseColour = water * diffuseIntensity;
    waterDiffuseColour.xy *= attenuation;

    float3 diffuseColour(0);
    float3 specularColour(0);

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
      waterDiffuseColour = waterDiffuseColour * (1.0 - specularFade);
    }
    
    if (is_terrain) {
      diffuseColour = mix(diffuseColour, waterDiffuseColour, 0.9);
    } else {
      // TODO: include skybox?
      diffuseColour = waterDiffuseColour;
    }
    
    lit = ambientColour + diffuseColour + specularColour;
#endif
  }

  // Gamma correction.
  lit = pow(lit, float3(1.0/1.8));
  return float4(lit, 1);
}
