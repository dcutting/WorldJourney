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
  bool is_terrain = albedo.a > 0.1;
  if (!is_terrain) {
    return float4(terrain.skyColour, 1);
  }
  bool is_dark_side = albedo.r > 0.1;
  float3 normal = normalTexture.sample(sample, in.uv).xyz;
  if (uniforms.renderMode == 1) {
    return float4((normal + 1) / 2, 1);
  }
  float diffuse = saturate(dot(normalize(normal), -normalize(uniforms.sunDirection)));

  float4 position = positionTexture.sample(sample, in.uv);
  float flatness = dot(normal, normalize(position.xyz));
  float height = length(position.xyz) - terrain.sphereRadius;

  float3 rock(0x96/255.0, 0x59/255.0, 0x2F/255.0);
  float3 snow(1);
  float3 grass = float3(.663, .80, .498);

  float snowLevel = (normalised_poleness(position.y, terrain.sphereRadius)) * terrain.fractal.amplitude;
  float snow_epsilon = terrain.fractal.amplitude / 4;
  float plainstep = smoothstep(snowLevel - snow_epsilon, snowLevel + snow_epsilon, height);
  float stepped = smoothstep(0.9, 0.96, flatness);
  float3 plain = mix(rock, grass, stepped);
  float3 colour = mix(plain, snow, plainstep);
  
  float shadowed = 0.0;
  if (is_dark_side) {
    shadowed = diffuse;
  }
  bool useRayMarchedShadows = false;
  if (useRayMarchedShadows) {
    float dist = distance_squared(uniforms.cameraPosition, position.xyz);
    
    float3 origin = position.xyz;
    
    float max_dist = 1000;
    
    Fractal fractal = terrain.fractal;
    fractal.octaves = 3;

    float min_step_size = clamp(dist, 1.0, 50.0);
    float step_size = min_step_size;
    for (float d = step_size; d < max_dist; d += step_size) {
      float3 tp = origin - uniforms.sunDirection * d;
      if (length(tp) > terrain.sphereRadius + terrain.fractal.amplitude) {
        break;
      }
      
      float3 w = normalize(tp) * terrain.sphereRadius;
      float height = sample_terrain(w, fractal).x;
      float diff = length(tp) - terrain.sphereRadius - height;
      if (diff < 0) {
        shadowed = diffuse;
        break;
      }
      min_step_size *= 2;
      step_size = max(min_step_size, diff/2);
    }
  }

  float3 lit = saturate(uniforms.ambient + diffuse - shadowed) * uniforms.sunColour * colour;
//  if (shadowed > 0) {
//    lit = float3(1.0, 1.0, 0.0);
//  }

  return float4(lit, 1);
}
