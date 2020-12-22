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
  float3 normal = normalize(normalTexture.sample(sample, in.uv).xyz);
  if (uniforms.renderMode == 1) {
    return float4((normal + 1) / 2, 1);
  }
  float4 position = positionTexture.sample(sample, in.uv);
  float3 toSun = normalize(uniforms.sunPosition - position.xyz);
  float diffuseIntensity = max(dot(normal, toSun), 0.0);

//  float flatness = dot(normal, normalize(position.xyz));
  
  float3 diffuseColour(0, 1, 1);
  
  if (is_terrain) {
    float height = length(position.xyz) - terrain.sphereRadius;

    float3 snow(0.2);
  //  float3 grass = float3(.663, .80, .498);

    float snowLevel = terrain.snowLevel;// (normalised_poleness(position.y, terrain.sphereRadius)) * terrain.fractal.amplitude;
    float snow_epsilon = terrain.fractal.amplitude / 4;
    float plainstep = smoothstep(snowLevel - snow_epsilon, snowLevel + snow_epsilon, height);
  //  float stepped = smoothstep(0.9, 0.96, flatness);
    float3 plain = terrain.groundColour;// mix(terrain.groundColour, grass, stepped);
    diffuseColour = mix(plain, snow, plainstep);
  } else if (is_object) {
    diffuseColour = float3(1, 1, 0);
  }
  
  float3 diffuse = diffuseColour * diffuseIntensity;

  float3 specular = 0;
  if (is_terrain && terrain.shininess > 0 && diffuseIntensity > 0) {
    float3 reflection = reflect(-toSun, normal);
    float3 toEye = normalize(uniforms.cameraPosition - position.xyz);
    float specularIntensity = pow(max(dot(reflection, toEye), 0.0), terrain.shininess);
    specular = uniforms.sunColour * specularIntensity;
  }
  float brightness = albedo.a;

#if 0
  //    float dist = distance_squared(uniforms.cameraPosition, worldPosition);
          
      float3 origin = position.xyz;
      
      float max_dist = 10000;
      float rayLength = max_dist;
      
      Fractal fractal = terrain.fractal;
//      fractal.octaves = 2;
      
      float3 sunDirection = normalize(uniforms.sunPosition - origin);
  
      float3 pDir = normalize(origin);
      float terminator = dot(pDir, sunDirection);
      float terminatorEpsilon = 2;
      if (terminator < -terminatorEpsilon) {
        brightness = 0.0;
      } else if (terminator > terminatorEpsilon) {
        brightness = 1.0;
      } else {
      
      float lh = 0;
      float ly = 0;
      float min_step_size = 0.5;
      float step_size = min_step_size;
      for (float d = step_size; d < max_dist; d += step_size) {
        float3 tp = origin + sunDirection * d;
        if (length(tp) > terrain.sphereRadius + terrain.fractal.amplitude) {
          break;
        }
        
        float3 w = normalize(tp) * terrain.sphereRadius;
        float height = sample_terrain(w, fractal).x;
        float py = length(tp) - terrain.sphereRadius;
        if (py < height) {
          rayLength = d - step_size*(lh-ly)/(py-ly-height+lh);
          break;
        }
        lh = height;
        ly = py;
        step_size = 1.01f*d;
  //      min_step_size *= 2;
  //      step_size = max(min_step_size, diff/2);
      }
      
  //    brightness = rayLength < max_dist ? 0 : 1;
      brightness = smoothstep(0, max_dist, rayLength);
      }
#endif
  
//  float brightness = albedo.a;
  float3 lit = uniforms.ambientColour + (diffuse + specular) * brightness;

  // Gamma correction.
  lit = pow(lit, float3(1.0/2.2));

  return float4(lit, 1);
}
