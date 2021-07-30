#include <metal_stdlib>
#include "Common.h"
#include "Terrain.h"
#include "Noise.h"

using namespace metal;


constant bool isOcean [[function_constant(0)]];

/** gbuffer vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float depth;
  float height;
  int octaves;
  float4 clipPosition [[position]];
  float3 modelPosition;
  float3 worldPosition;
  float3 worldGradient;
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
  
  Fractal fractal = terrain.fractal;

  float r = terrain.sphereRadius;
  float R = terrain.sphereRadius + (fractal.amplitude / 2.0);

  float3 unitGroundLevel = float3(interpolated.x, interpolated.y, 0);
  float3 p = unitGroundLevel;

  float d_sq = length_squared(uniforms.cameraPosition);
  float3 eye = uniforms.cameraPosition;
  
  // TODO
//  float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d_sq, eye);
//  float3 modelled = unit_spherical * R;
//  float tbd = pow(distance(eye, modelled), 0.5);
//  float tbds = clamp(tbd / 100.0, 0.0, 1.0);
//  float min_octaves = fractal.waveCount;
//  float max_octaves = min_octaves;
//  float no = (float)max_octaves * (1-tbds);
//  int new_octaves = clamp(no, min_octaves, max_octaves);
//  fractal.octaves = (int)new_octaves;
//  fractal.waveCount = (int)new_octaves;
  
  TerrainSample sample;
  
  if (isOcean) {
    sample = sample_ocean_michelic(p,
                                   r,
                                   R,
                                   d_sq,
                                   eye,
                                   terrain,
                                   fractal,
                                   uniforms.time);
  } else {
    sample = sample_terrain_michelic(p,
                                     r,
                                     R,
                                     d_sq,
                                     eye,
                                     terrain,
                                     fractal);
  }
    
  float depth = sample.depth;
  
  float height = sample.height;

  float3 worldPosition = sample.position;
  
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPosition, 1);
  
  float3 modelPosition = unitGroundLevel;
  
  float3 worldGradient;
  
  if (isOcean) {
    // Ocean is already in world system.
    worldGradient = sample.gradient;
  } else {
    // Terrain needs to be converted to world system.
    worldGradient = sphericalise_flat_gradient(sample.gradient, terrain.fractal.amplitude, normalize(worldPosition));
  }
  
  return {
    .depth = depth,
    .height = height,
    .octaves = fractal.octaves,
    .clipPosition = clipPosition,
    .modelPosition = modelPosition,
    .worldPosition = worldPosition,
    .worldGradient = worldGradient
  };
}



/** gbuffer fragment shader */

struct GbufferOut {
  // TODO: may be able to get rid of albedo and just rely on position.
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

constexpr sampler s(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> closeNormalMap [[texture(0)]],
                                     texture2d<float> mediumNormalMap [[texture(1)]]) {

  float3 unitSurfacePoint = normalize(in.worldPosition);
  float3 worldNormal = normalize(in.worldGradient);
  
  float3 mappedNormal;
  
  // https://stackoverflow.com/questions/21210774/normal-mapping-on-procedural-sphere
  // https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a
  if (USE_NORMAL_MAPS && !isOcean) {
//    float3 mediumNormalMapValue = boxmap(in.worldPosition / 400, worldNormal, 3, mediumNormalMap).xyz;
//    float3 closeNormalMapValue = normalize(boxmap(in.worldPosition / 1, worldNormal, 1, closeNormalMap).xyz);
//    float3 normalMapValue = normalize(closeNormalMapValue);// + mediumNormalMapValue * 0.5) - 0.4;
    
    float3 p = in.worldPosition;

    // UDN blend
    // Triplanar uvs
    float2 uvX = p.zy; // x facing plane
    float2 uvY = p.xz; // y facing plane
    float2 uvZ = p.xy; // z facing plane
    // Tangent space normal maps
//    half3 tnormalX = UnpackNormal(tex2D(_BumpMap, uvX));
//    half3 tnormalY = UnpackNormal(tex2D(_BumpMap, uvY));
//    half3 tnormalZ = UnpackNormal(tex2D(_BumpMap, uvZ));
    float3 tnormalX = closeNormalMap.sample(s, uvX).xyz;
    float3 tnormalY = closeNormalMap.sample(s, uvY).xyz;
    float3 tnormalZ = closeNormalMap.sample(s, uvZ).xyz;

    // Swizzle world normals into tangent space and apply UDN blend.
    // These should get normalized, but it's very a minor visual
    // difference to skip it until after the blend.
    tnormalX = float3(tnormalX.xy + worldNormal.zy, worldNormal.x);
    tnormalY = float3(tnormalY.xy + worldNormal.xz, worldNormal.y);
    tnormalZ = float3(tnormalZ.xy + worldNormal.xy, worldNormal.z);
    // Swizzle tangent normals to match world orientation and triblend
    float3 blend = abs(worldNormal.xyz);
    blend /= blend.x + blend.y + blend.z;
    mappedNormal = normalize(
        tnormalX.zyx * blend.x +
        tnormalY.xzy * blend.y +
        tnormalZ.xyz * blend.z
        );


  } else {
    mappedNormal = worldNormal;
  }
  mappedNormal = normalize(mappedNormal);
  
  float4 albedo = float4(isOcean ? 1 : 0, isOcean ? 0 : 1, 0, 1);
  
  float3 normal = mappedNormal;
  
  float3 position = in.worldPosition;
  
  return {
    .albedo = albedo,
    .normal = float4(normal, 1),
    .position = float4(position, 1)
  };
}
