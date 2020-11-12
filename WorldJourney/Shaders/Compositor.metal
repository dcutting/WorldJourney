#include <metal_stdlib>
#include "../Common.h"
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
  bool is_terrain = albedo.g > 0.5;
  bool is_object = albedo.r > 0.5;
  if (!is_terrain && !is_object) {
    return float4(terrain.skyColour, 1);
  }
  float3 normal = normalize(normalTexture.sample(sample, in.uv).xyz);
  if (uniforms.renderMode == 1) {
    return float4((normal + 1) / 2, 1);
  }
  float diffuse = saturate(dot(normal, -normalize(uniforms.sunDirection)));

  float4 position = positionTexture.sample(sample, in.uv);
//  float flatness = dot(normal, normalize(position.xyz));
  
  float3 colour(0, 1, 1);
  
  if (is_terrain) {
    float height = length(position.xyz) - terrain.sphereRadius;

    float3 snow(1);
  //  float3 grass = float3(.663, .80, .498);

    float snowLevel = terrain.snowLevel;// (normalised_poleness(position.y, terrain.sphereRadius)) * terrain.fractal.amplitude;
    float snow_epsilon = terrain.fractal.amplitude / 4;
    float plainstep = smoothstep(snowLevel - snow_epsilon, snowLevel + snow_epsilon, height);
  //  float stepped = smoothstep(0.9, 0.96, flatness);
    float3 plain = terrain.groundColour;// mix(terrain.groundColour, grass, stepped);
    colour = mix(plain, snow, plainstep);
  } else if (is_object) {
    colour = float3(1, 1, 0);
  }
  
  float3 specularColor = 0;
  if (is_terrain && terrain.shininess > 0) {
    // TODO: some bug here makes opposite sides shiny (or something).
    float3 materialSpecularColor = float3(1, 1, 1);
    float3 cameraDirection = normalize(position.xyz - uniforms.cameraPosition);
    float3 reflection = reflect(normalize(-uniforms.sunDirection), normal);
    float specularIntensity = pow(saturate(dot(reflection, cameraDirection)), terrain.shininess);
    specularColor = uniforms.sunColour * materialSpecularColor * specularIntensity;
  }

  float brightness = albedo.a;
  float3 lit = (uniforms.ambient + (diffuse + specularColor) * brightness) * uniforms.sunColour * colour;
//  if (shadowed > 0) {
//    lit = float3(1.0, 1.0, 0.0);
//  }

  return float4(lit, 1);
}
