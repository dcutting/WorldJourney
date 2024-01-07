// https://github.com/metal-by-example/modelio-materials

#include <metal_stdlib>
#include "Common.h"
#include "../Shared/Maths.h"
#include "../Shared/Terrain.h"

using namespace metal;

enum {
  textureIndexBaseColor = 4,
  textureIndexMetallic = 5,
  textureIndexRoughness = 6,
  textureIndexNormal = 7,
  textureIndexEmissive = 8
//  textureIndexIrradiance = 9
};

enum {
  vertexBufferIndexUniforms = 1,
  vertexBufferIndexInstanceUniforms = 2,
  vertexBufferIndexTerrain = 3
};

enum {
  fragmentBufferIndexUniforms = 0
};

struct Vertex {
  float3 position  [[attribute(0)]];
  float3 normal    [[attribute(1)]];
  float3 tangent   [[attribute(2)]];
  float2 texCoords [[attribute(3)]];
};

struct VertexOut {
  float4 position [[position]];
  float2 texCoords;
  float3 worldPos;
  float3 normal;
  float3 bitangent;
  float3 tangent;
};

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

struct LightingParameters {
  float3 lightDir;
  float3 viewDir;
  float3 halfVector;
  float3 reflectedVector;
  float3 normal;
  float3 reflectedColor;
  float3 irradiatedColor;
  float3 baseColor;
  float3 diffuseLightColor;
  float  NdotH;
  float  NdotV;
  float  NdotL;
  float  HdotL;
  float  metalness;
  float  roughness;
};

#define SRGB_ALPHA 0.055

float linear_from_srgb(float x) {
  if (x <= 0.04045)
    return x / 12.92;
  else
    return powr((x + SRGB_ALPHA) / (1.0 + SRGB_ALPHA), 2.4);
}

float3 linear_from_srgb(float3 rgb) {
  return float3(linear_from_srgb(rgb.r), linear_from_srgb(rgb.g), linear_from_srgb(rgb.b));
}

vertex VertexOut objects_vertex(Vertex in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(vertexBufferIndexUniforms)]],
                                constant InstanceUniforms *instanceUniforms [[buffer(vertexBufferIndexInstanceUniforms)]],
                                constant Terrain &terrain [[buffer(vertexBufferIndexTerrain)]],
                                ushort iid [[instance_id]])
{
  float3 coordinate = normalize(instanceUniforms[iid].coordinate);
  TerrainSample sample = sample_terrain_spherical(coordinate, terrain.sphereRadius, terrain, terrain.fractal);
  matrix_float4x4 modelMatrix = translate(sample.position) * scale(instanceUniforms[iid].scale) * instanceUniforms[iid].transform;
  matrix_float3x3 modelMatrixIT = normalMatrix(modelMatrix);
  float4 worldPosition = modelMatrix * float4(in.position, 1);

  VertexOut out;
  out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
  out.texCoords = in.texCoords;
  out.normal = modelMatrixIT * in.normal;
  out.tangent = modelMatrixIT * in.tangent;
  out.bitangent = modelMatrixIT * cross(in.normal, in.tangent);
  out.worldPos = worldPosition.xyz;
  return out;
}

static float3 diffuseTerm(LightingParameters parameters) {
  float3 diffuseColor = (parameters.baseColor.rgb / M_PI_F) * (1.0 - parameters.metalness);
  return diffuseColor * parameters.NdotL * parameters.diffuseLightColor;
}

static float SchlickFresnel(float dotProduct) {
  return pow(clamp(1.0 - dotProduct, 0.0, 1.0), 5.0);
}

static float Geometry(float NdotV, float alphaG) {
  float a = alphaG * alphaG;
  float b = NdotV * NdotV;
  return 1.0 / (NdotV + sqrt(a + b - a * b));
}

static float TrowbridgeReitzNDF(float NdotH, float roughness) {
  if (roughness >= 1.0)
    return 1.0 / M_PI_F;
  
  float roughnessSqr = roughness * roughness;
  
  float d = (NdotH * roughnessSqr - NdotH) * NdotH + 1;
  return roughnessSqr / (M_PI_F * d * d);
}

static float3 specularTerm(LightingParameters parameters) {
  float specularRoughness = parameters.roughness * (1.0 - parameters.metalness) + parameters.metalness;
  
  float D = TrowbridgeReitzNDF(parameters.NdotH, specularRoughness);
  
  float Cspec0 = 0.04;
  float3 F = mix(Cspec0, 1, SchlickFresnel(parameters.HdotL));
  float alphaG = powr(specularRoughness * 0.5 + 0.5, 2);
  float G = Geometry(parameters.NdotL, alphaG) * Geometry(parameters.NdotV, alphaG);
  
  float3 specularOutput = (D * G * F * parameters.irradiatedColor) * (1.0 + parameters.metalness * parameters.baseColor) +
  parameters.irradiatedColor * parameters.metalness * parameters.baseColor;
  
  return specularOutput;
}

fragment GbufferOut objects_fragment(VertexOut in                     [[stage_in]],
                             constant Uniforms &uniforms      [[buffer(fragmentBufferIndexUniforms)]],
                             texture2d<float> baseColorMap    [[texture(textureIndexBaseColor)]],
                             texture2d<float> metallicMap     [[texture(textureIndexMetallic)]],
                             texture2d<float> roughnessMap    [[texture(textureIndexRoughness)]],
                             texture2d<float> normalMap       [[texture(textureIndexNormal)]],
                             texture2d<float> emissiveMap     [[texture(textureIndexEmissive)]])
//                             texturecube<float> irradianceMap [[texture(textureIndexIrradiance)]])
{
  
  constexpr sampler linearSampler (mip_filter::linear, mag_filter::linear, min_filter::linear);
//  constexpr sampler mipSampler(min_filter::linear, mag_filter::linear, mip_filter::linear);
  constexpr sampler normalSampler(filter::nearest);
  
  const float3 diffuseLightColor(4);
  
  LightingParameters parameters;
  
  float4 baseColor = baseColorMap.sample(linearSampler, in.texCoords);
  parameters.baseColor = linear_from_srgb(baseColor.rgb);
  parameters.roughness = roughnessMap.sample(linearSampler, in.texCoords).g;
  parameters.metalness = metallicMap.sample(linearSampler, in.texCoords).b;
  float3 mapNormal = normalMap.sample(normalSampler, in.texCoords).rgb * 2.0 - 1.0;
  //mapNormal.y = -mapNormal.y; // Flip normal map Y-axis if necessary
  float3x3 TBN(in.tangent, in.bitangent, in.normal);
  parameters.normal = normalize(TBN * mapNormal);
  
  parameters.diffuseLightColor = diffuseLightColor;
  parameters.lightDir = normalize(uniforms.sunPosition - in.worldPos);// uniforms.directionalLightInvDirection;
  parameters.viewDir = normalize(uniforms.cameraPosition - in.worldPos);
  parameters.halfVector = normalize(parameters.lightDir + parameters.viewDir);
  parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);
  
  parameters.NdotL = saturate(dot(parameters.normal, parameters.lightDir));
  parameters.NdotH = saturate(dot(parameters.normal, parameters.halfVector));
  parameters.NdotV = saturate(dot(parameters.normal, parameters.viewDir));
  parameters.HdotL = saturate(dot(parameters.lightDir, parameters.halfVector));
  
//  float mipLevel = parameters.roughness * irradianceMap.get_num_mip_levels();
  parameters.irradiatedColor = float3(1);// irradianceMap.sample(mipSampler, parameters.reflectedVector, level(mipLevel)).rgb;
  
  float3 emissiveColor = emissiveMap.sample(linearSampler, in.texCoords).rgb;
  
  float3 color = diffuseTerm(parameters) + specularTerm(parameters) + emissiveColor;
  
  float4 albedo = float4(color, baseColor.a);
  
  return {
    .albedo = albedo,
    .normal = float4(normalize(in.normal), 1),
    .position = float4(in.worldPos, 1)
  };
}
