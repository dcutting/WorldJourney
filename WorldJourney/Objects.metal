#include <metal_stdlib>
#include "Common.h"

using namespace metal;

enum {
    textureIndexBaseColor,
    textureIndexMetallic,
    textureIndexRoughness,
    textureIndexNormal,
    textureIndexEmissive,
    textureIndexIrradiance = 9
};

struct ObjectIn {
  float3 position [[attribute(0)]];
  float3 normal [[attribute(1)]];
  float3 tangent [[attribute(2)]];
  float2 texCoords [[attribute(3)]];
};

struct ObjectOut {
  float4 clipPosition [[position]];
  float4 worldPosition;
  float3 normal;
  float3 tangent;
  float3 bitangent;
  float2 texCoords;
};

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

vertex ObjectOut object_vertex(ObjectIn vertexIn [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               constant InstanceUniforms *instanceUniforms [[buffer(2)]],
                               texture2d<float> baseColorMap    [[texture(0)]],
                               texture2d<float> metallicMap     [[texture(1)]],
                               texture2d<float> roughnessMap    [[texture(2)]],
                               texture2d<float> normalMap       [[texture(3)]],
                               texture2d<float> emissiveMap     [[texture(4)]],
                               texturecube<float> irradianceMap [[texture(5)]],
                               ushort iid [[instance_id]]) {
  matrix_float4x4 modelMatrix = instanceUniforms[iid].modelMatrix;
  float4 worldPosition = modelMatrix * float4(vertexIn.position, 1);
  matrix_float4x4 modelMatrixIT = instanceUniforms[iid].modelNormalMatrix;

  ObjectOut vertexOut;
  vertexOut.clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
  vertexOut.worldPosition = worldPosition;
  vertexOut.normal = (modelMatrixIT * float4(normalize(vertexIn.normal), 1)).xyz;
  vertexOut.tangent = (modelMatrixIT * float4(normalize(vertexIn.tangent), 1)).xyz;
  vertexOut.bitangent = (modelMatrixIT * float4(cross(normalize(vertexIn.normal), normalize(vertexIn.tangent)), 1)).xyz;
  vertexOut.texCoords = vertexIn.texCoords;
  return vertexOut;
}

//constexpr sampler s(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

//fragment GbufferOut object_fragment(ObjectOut in [[stage_in]],
//                                    constant Uniforms &uniforms [[buffer(0)]],
//                                    texture2d<float> texture [[texture(0)]]) {
//  float4 albedo = texture.sample(s, in.texCoords);
//  return {
//    .albedo = albedo,
//    .normal = float4(in.normal, 1),
//    .position = in.worldPosition
//  };
//}

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

fragment GbufferOut object_fragment(ObjectOut in                     [[stage_in]],
                             constant Uniforms &uniforms      [[buffer(0)]],
                             texture2d<float> baseColorMap    [[texture(textureIndexBaseColor)]],
                             texture2d<float> metallicMap     [[texture(textureIndexMetallic)]],
                             texture2d<float> roughnessMap    [[texture(textureIndexRoughness)]],
                             texture2d<float> normalMap       [[texture(textureIndexNormal)]],
                             texture2d<float> emissiveMap     [[texture(textureIndexEmissive)]],
                             texturecube<float> irradianceMap [[texture(textureIndexIrradiance)]])
{
    constexpr sampler linearSampler (mip_filter::linear, mag_filter::linear, min_filter::linear);
    constexpr sampler mipSampler(min_filter::linear, mag_filter::linear, mip_filter::linear);
    constexpr sampler normalSampler(filter::nearest);
    
    const float3 diffuseLightColor(4);

    LightingParameters parameters;

    float4 baseColor = baseColorMap.sample(linearSampler, in.texCoords);
    parameters.baseColor = linear_from_srgb(baseColor.rgb);
    parameters.roughness = roughnessMap.sample(linearSampler, in.texCoords).g;
    parameters.metalness = metallicMap.sample(linearSampler, in.texCoords).b;
    float3 mapNormal = normalMap.sample(normalSampler, in.texCoords).rgb * 2.0 - 1.0;
    //mapNormal.y = -mapNormal.y; // Flip normal map Y-axis if necessary
    float3x3 TBN(normalize(in.tangent), normalize(in.bitangent), normalize(in.normal));
    parameters.normal = normalize(TBN * mapNormal);

    parameters.diffuseLightColor = diffuseLightColor;
  parameters.lightDir = normalize(uniforms.sunPosition - in.worldPosition.xyz);// uniforms.directionalLightInvDirection;
    parameters.viewDir = normalize(uniforms.cameraPosition - in.worldPosition.xyz);
    parameters.halfVector = normalize(parameters.lightDir + parameters.viewDir);
    parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);

    parameters.NdotL = saturate(dot(parameters.normal, parameters.lightDir));
    parameters.NdotH = saturate(dot(parameters.normal, parameters.halfVector));
    parameters.NdotV = saturate(dot(parameters.normal, parameters.viewDir));
    parameters.HdotL = saturate(dot(parameters.lightDir, parameters.halfVector));

    float mipLevel = parameters.roughness * irradianceMap.get_num_mip_levels();
    parameters.irradiatedColor = irradianceMap.sample(mipSampler, parameters.reflectedVector, level(mipLevel)).rgb;
    
    float3 emissiveColor = emissiveMap.sample(linearSampler, in.texCoords).rgb;

  float3 color = diffuseTerm(parameters) + specularTerm(parameters) + emissiveColor;

  float4 albedo = float4(float3(color), baseColor.a);
    return {
      .albedo = albedo,
      .normal = float4(normalize(in.normal), 1),
      .position = in.worldPosition
    };
}
