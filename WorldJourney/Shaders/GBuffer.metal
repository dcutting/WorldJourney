#include <metal_stdlib>
#include "../Common.h"
#include "Terrain.h"
#include "../Noise/ProceduralNoise.h"

using namespace metal;



/** gbuffer vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float height;
  float brightness;
  float4 clipPosition [[position]];
  float3 modelPosition;
  float3 worldPosition;
  float3 modelGradient;
};

[[patch(quad, 4)]]
vertex EdenVertexOut gbuffer_vertex(patch_control_point<ControlPoint> control_points [[stage_in]],
                                    uint patchID [[patch_id]],
                                    float2 patch_coord [[position_in_patch]],
                                    constant Uniforms &uniforms [[buffer(1)]],
                                    constant Terrain &terrain [[buffer(2)]]) {
  
  float u = patch_coord.x;
  float v = patch_coord.y;
  float2 top = mix(control_points[0].position.xy, control_points[1].position.xy, u);
  float2 bottom = mix(control_points[3].position.xy, control_points[2].position.xy, u);
  float2 interpolated = mix(top, bottom, v);
  
  float height = control_points[0].position.z;
  float3 unitGroundLevel = float3(interpolated.x, interpolated.y, 0);
  float3 p = unitGroundLevel;
  
  float r = terrain.sphereRadius;
  float R = terrain.sphereRadius + terrain.fractal.amplitude;
  TerrainSample sample = sample_terrain_michelic(p,
                                                 r,
                                                 R,
                                                 length_squared(uniforms.cameraPosition),
                                                 uniforms.cameraPosition,
                                                 terrain.fractal);
  float3 worldPosition = sample.position;
  
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPosition, 1);
  
  float3 modelPosition = unitGroundLevel;
  
  float3 modelGradient = sample.gradient;
  
  float brightness = 1.0;
  
  int shadows = 2;
  
  if (shadows == 1) {
    float r_sq = powr(r, 2);
    float R_sq = powr(R, 2);
    float d_sq = length_squared(uniforms.sunPosition);
    float h_sq = d_sq - r_sq;
    float s_sq = R_sq - r_sq;
    float l_sq = h_sq + s_sq;
    float ws_sq = distance_squared(worldPosition, uniforms.sunPosition);
    brightness = smoothstep(0, r*20, sqrt(l_sq - ws_sq)); // TODO: not quite right calculation.
  } else if (shadows == 2) {
//    float dist = distance_squared(uniforms.cameraPosition, worldPosition);
        
    float3 origin = worldPosition;
    
    float max_dist = 10000;
    float rayLength = max_dist;
    
    Fractal fractal = terrain.fractal;
//    fractal.octaves = 4;
    
    float3 sunDirection = normalize(uniforms.sunPosition - worldPosition);
    
    float lh = 0;
    float ly = 0;
    float min_step_size = 1;//clamp(dist, 1.0, 50.0);
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
    brightness = smoothstep(100, 1000, rayLength);
  }

  return {
    .height = height,
    .brightness = brightness,
    .clipPosition = clipPosition,
    .modelPosition = modelPosition,
    .worldPosition = worldPosition,
    .modelGradient = modelGradient
  };
}



/** gbuffer fragment shader */

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

float4 boxmap(float3 p, float3 n, float k, texture2d<float> texture) {
  constexpr sampler s(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
  
  // project+fetch
  float4 x = texture.sample(s, p.yz);
  float4 y = texture.sample(s, p.zx);
  float4 z = texture.sample(s, p.xy);
  
  // blend factors
  float3 w = pow(abs(n), float3(k));
  // blend and return
  return (x*w.x + y*w.y + z*w.z) / (w.x + w.y + w.z);
}

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> normalMap [[texture(0)]],
                                     texture2d<float> normalMap2 [[texture(1)]]) {

  float3 unitSurfacePoint = normalize(in.worldPosition);
  
  float3 worldNormal = sphericalise_flat_gradient(in.modelGradient, terrain.fractal.amplitude, unitSurfacePoint);
  float3 worldTangent = sphericalise_flat_gradient(float3(1, 0, 0), terrain.fractal.amplitude, unitSurfacePoint);
  float3 worldBitangent = sphericalise_flat_gradient(float3(0, 1, 0), terrain.fractal.amplitude, unitSurfacePoint);
  
  float3 mappedNormal = worldNormal;

  bool useNormalMaps = true;
  if (useNormalMaps) {
    float3 normalMapValue;
    bool proceduralNormalMapping = false;
    if (proceduralNormalMapping) {
      float3 p = in.worldPosition;
      float3 mediumNormalMapValue = simplex_noised_3d(p / 200).xyz * 2.0 - 1.0;
      float3 closeNormalMapValue = simplex_noised_3d(p / 10).xyz * 2.0 - 1.0;
      normalMapValue = normalize(closeNormalMapValue * 0.3 + mediumNormalMapValue * 0.8);
    } else {
      float3 mediumNormalMapValue = boxmap(in.worldPosition / 400, worldNormal, 3, normalMap2).xyz;
      float3 closeNormalMapValue = boxmap(in.worldPosition / 10, worldNormal, 3, normalMap).xyz;
      normalMapValue = (closeNormalMapValue * 0.5 + mediumNormalMapValue * 0.5) - 0.5;
    }
    mappedNormal = worldNormal * normalMapValue.z + worldTangent * normalMapValue.x + worldBitangent * normalMapValue.y;
  }
  
  float4 albedo = float4(0, 1, 0, in.brightness);

  return {
    .albedo = albedo,
    .normal = float4(normalize(mappedNormal), 1),
    .position = float4(in.worldPosition, 1)
  };
}
