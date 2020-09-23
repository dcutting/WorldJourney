#include <metal_stdlib>
#include "Common.h"
using namespace metal;

constant float3 ambientIntensity = 0.15;
constant float3 lightColour(1.0);



/** composition vertex shader */

struct CompositionOut {
  float4 position [[position]];
  float2 uv;
};

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
                                     texture2d<float> rockTexture [[texture(3)]],
                                     texture2d<float> heightMap [[texture(5)]],
                                     texture2d<float> noiseMap [[texture(6)]],
                                     texture2d<float> normalMap [[texture(7)]],
                                     texturecube<float> skyTexture [[texture(8)]]) {
  
  constexpr sampler sample(min_filter::linear, mag_filter::linear);
  
  float2 v_texCoord = in.uv;
  float2 uv = v_texCoord;
  
  float4 albedo = albedoTexture.sample(sample, uv);
  
  float4 ptex = positionTexture.sample(sample, uv);
  float3 position = ptex.xyz;
  float raw_height = ptex.a * terrain.fractal.amplitude;
  
  float2 uvn = uv - float2(0.5);
  float aspect = albedoTexture.get_width() / albedoTexture.get_height();
  uvn.x *= aspect;
  //TODO sun is not quite in the right position...
  float4 pmatrix = float4(normalize(float3(uvn.x, -uvn.y, -0.9)), 1);
  float3 cameraDirection = normalize((transpose(uniforms.viewMatrix) * pmatrix).xyz);
  
  float3 sky_color = float3(0xE3/255.0, 0x9E/255.0, 0x50/255.0);
  
  float atmosphere_transition_edge = 10000.0;
  float atmosphere_thickness = 20000.0;
  float atmosphereness = smoothstep(atmosphere_transition_edge, atmosphere_thickness, uniforms.cameraPosition.y);
  
  float3 sun_colour = float3(0xFB/255.0, 0xFC/255.0, 0xCD/255.0);
  float3 light_dir = normalize(-uniforms.lightDirection);
  float samesame = dot(cameraDirection, light_dir);
  float3 scene_color = mix(sky_color, float3(0, 0, 0), atmosphereness);
  scene_color = mix(scene_color, sun_colour, saturate(pow(samesame, 100)));
  
  if (albedo.a > 0.1) {
    
    float3 normal = normalTexture.sample(sample, uv).xyz;
    
    if (uniforms.renderMode == 1) {
      scene_color = normal;
    } else if (uniforms.renderMode == 2) {
      float height = raw_height / terrain.fractal.amplitude;
      float3 height_colour = float3(0.2, 0.0, height);
      scene_color = height_colour;
    } else {
      
      float3 L = light_dir;
      
      if (albedo.a < 0.5) {
        float3 rock = float3(0x96/255.0, 0x59/255.0, 0x2F/255.0);
        float3 snow = float3(1);
        //        float3 grass = float3(.663, .80, .498);
        float3 ground = rock;
        float3 cliff = rock;
        
        float flatness = dot(normal, float3(0, 1, 0));
        
        float stepped = smoothstep(0.85, 1.0, flatness);
        float plainstep = smoothstep(terrain.snowLevel * 0.9, terrain.snowLevel, raw_height);
        float3 plain = mix(ground, snow, plainstep);
        float3 c = mix(cliff, plain, stepped);
        c = mix(c, sky_color, atmosphereness/2);
        albedo = float4(c, 1);
      }
      
      float diffuseIntensity = saturate(dot(normal, L));
      
      float3 specularColor = 0;
      float materialShininess = 256;
      float3 materialSpecularColor = float3(1, 1, 1);
      
      float3 cameraDirection = normalize(position - uniforms.cameraPosition);
      
      if (diffuseIntensity > 0 && raw_height < terrain.waterLevel+1) {
        float3 reflection = reflect(L, normal);
        float specularIntensity = pow(saturate(dot(reflection, cameraDirection)), materialShininess);
        specularColor = lightColour * materialSpecularColor * specularIntensity;
      }
      
      scene_color = saturate(ambientIntensity + diffuseIntensity + specularColor) * lightColour * albedo.xyz;
    }
  }
  
  return float4(scene_color, 1.0);
}
