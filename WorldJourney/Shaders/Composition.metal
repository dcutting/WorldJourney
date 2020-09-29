#include <metal_stdlib>
#include "Common.h"

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
  float3 normal = normalTexture.sample(sample, in.uv).xyz;
  if (uniforms.renderMode == 1) {
    return float4((normal + 1) / 2, 1);
  }
  float diffuse = saturate(dot(normal, -uniforms.sunDirection));

  float4 position = positionTexture.sample(sample, in.uv);
  float flatness = dot(normal, normalize(position.xyz));
  float height = length(position.xyz) - terrain.sphereRadius;

  float3 rock(0x96/255.0, 0x59/255.0, 0x2F/255.0);
  float3 snow(1);
  float3 grass = float3(.663, .80, .498);

  float plainstep = smoothstep(terrain.snowLevel - terrain.fractal.amplitude / 2, terrain.snowLevel, height);
  float3 plain = mix(grass, snow, plainstep);
  float stepped = smoothstep(0.97, 1.0, flatness);
  float3 colour = mix(rock, plain, stepped);
  
  float3 lit = saturate(uniforms.ambient + diffuse) * uniforms.sunColour * colour;
  return float4(lit, 1);
}
