#include <metal_stdlib>
using namespace metal;

#include "Common.h"

constant float3 ambientIntensity = 0.3;
constant float3 lightWorldPosition(TERRAIN_SIZE*2, TERRAIN_SIZE*2, TERRAIN_SIZE*2);
constant float3 lightColour(1.0);

constexpr sampler mirrored_sample(coord::normalized, address::mirrored_repeat, filter::linear);
constexpr sampler repeat_sample(coord::normalized, address::repeat, filter::linear);

struct VertexOut {
  float4 position [[position]];
  float2 texCoords;
};

vertex VertexOut composition_vertex(
                                 constant float2 *quadVertices [[buffer(0)]],
                                 constant float2 *quadTexCoords [[buffer(1)]],
                                 uint id [[vertex_id]])
{
  VertexOut out;
  out.position = float4(quadVertices[id], 0.0, 1.0);
  out.texCoords = quadTexCoords[id];
  return out;
}

fragment float4 composition_fragment(VertexOut in [[stage_in]],
                                     constant Uniforms &fragmentUniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     //                                constant Light *lightsBuffer [[buffer(2)]],
                                     texture2d<float> albedoTexture [[texture(0)]],
                                     texture2d<float> normalTexture [[texture(1)]],
                                     texture2d<float> positionTexture [[texture(2)]],
                                     texture2d<float> rockTexture [[texture(3)]],
                                     texture2d<float> snowTexture [[texture(4)]])
//                                depth2d<float> shadowTexture [[texture(4)]])
{

    constexpr sampler s(min_filter::linear, mag_filter::linear);

//    float4 albedo = albedoTexture.sample(s, in.texCoords);

    float3 N = normalTexture.sample(s, in.texCoords).xyz;
        float3 position = positionTexture.sample(s, in.texCoords).xyz;
        float3 L = normalize(lightWorldPosition - position);
        float flatness = dot(N, float3(0, 1, 0));
    //    float ds = distance_squared(uniforms.cameraPosition, in.worldPosition) / ((terrain.size * terrain.size));
//        float3 rockFar = rockTexture.sample(repeat_sample, in.worldPosition.xz / 50).xyz;
        float3 rockClose = rockTexture.sample(repeat_sample, position.xz / 30).xyz;
        float3 rock = rockClose;//mix(rockClose, rockFar, saturate(ds * 5000));
    //    float3 snowFar = snowTexture.sample(repeat_sample, in.worldPosition.xz / 30).xyz;
//        float3 snowClose = snowTexture.sample(repeat_sample, position.xz / 5).xyz;
        float3 snow = float3(1);//mix(snowClose, snowFar, saturate(ds * 500));
        float stepped = smoothstep(0.75, 1.0, flatness);
        float3 c = mix(rock, snow, stepped);
//    float3 c = albedo.xyz;
        float3 diffuseIntensity = saturate(dot(N, L));
        float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColour * c;
        return float4(finalColor, 1);

    
//  float4 albedo = albedoTexture.sample(s, in.texCoords);
//  float3 normal = normalTexture.sample(s, in.texCoords).xyz;
//  float3 position = positionTexture.sample(s, in.texCoords).xyz;
//  float3 baseColor = albedo.rgb;
//    float3 diffuseColor = albedo.xyz;//.xyz;//float3(1,0,0.5);// compositeLighting(normal, position,
////                                          fragmentUniforms, lightsBuffer, baseColor);
////  float shadow = albedo.a;
////  if (shadow > 0) {
////    diffuseColor *= 0.5;
////  }
//  return float4(diffuseColor, 1);
}
