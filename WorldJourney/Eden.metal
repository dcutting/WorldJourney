#include <metal_stdlib>
#include "Common.h"
using namespace metal;

constant float3 ambientIntensity = 0.2;
constant float3 lightWorldPosition(200, 200, 50);
constant float3 lightColour(1.0);

float calc_distance(float3 pointA, float3 pointB, float3 camera_position, float4x4 model_matrix) {
    float3 positionA = (model_matrix * float4(pointA, 1)).xyz;
    float3 positionB = (model_matrix * float4(pointB, 1)).xyz;
    float3 midpoint = (positionA + positionB) * 0.5;
    float camera_distance = distance(camera_position, midpoint);
    return camera_distance;
}

kernel void eden_tessellation(constant float *edge_factors [[buffer(0)]],
                              constant float *inside_factors [[buffer(1)]],
                              device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                              constant float3 *control_points [[buffer(3)]],
                              constant Uniforms &uniforms [[buffer(4)]],
                              constant Terrain &terrain [[buffer(5)]],
                              uint pid [[thread_position_in_grid]]) {
    
    uint index = pid * 4;
    float totalTessellation = 0;
    for (int i = 0; i < 4; i++) {
        int pointAIndex = i;
        int pointBIndex = i + 1;
        if (pointAIndex == 3) {
            pointBIndex = 0;
        }
        int edgeIndex = pointBIndex;
        float cameraDistance = calc_distance(control_points[pointAIndex + index],
                                             control_points[pointBIndex + index],
                                             uniforms.cameraPosition,
                                             uniforms.modelMatrix);
        float tessellation = max(16.0, terrain.tessellation / (cameraDistance / 4));
        factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
        totalTessellation += tessellation;
    }
    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}

typedef struct {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
} EdenVertexOut;

struct ControlPoint {
    float4 position [[attribute(0)]];
};

constexpr sampler mirrored_sample(coord::normalized, address::mirrored_repeat, filter::linear);
constexpr sampler repeat_sample(coord::normalized, address::mirrored_repeat, filter::linear);

float random(float2 st, texture2d<float> noiseMap) {
    return noiseMap.sample(mirrored_sample, st).r;
}

float fbm(float2 st, float frequency, texture2d<float> noiseMap) {
    float value = 0.0;
    float amplitude = .5;
    
    float2 stf = st * frequency;
    
    for (int i = 0; i < 5; i++) {
        value += amplitude * random(stf * (i+1), noiseMap);
        amplitude *= .5;
   }
   return value;
}

float terrain_height_noise(float2 xz, Terrain terrain, texture2d<float> heightMap, texture2d<float> noiseMap) {
    float4 color = heightMap.sample(mirrored_sample, xz);
    float coarse = color.r * terrain.height;
    float noise = fbm(xz, terrain.frequency, noiseMap);
    return coarse + noise;
}

[[patch(quad, 4)]]
vertex EdenVertexOut eden_vertex(patch_control_point<ControlPoint>
                                 control_points [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]],
                                 constant Terrain &terrain [[buffer(2)]],
                                 texture2d<float> heightMap [[texture(0)]],
                                 texture2d<float> noiseMap [[texture(1)]],
                                 uint patchID [[patch_id]],
                                 float2 patch_coord [[position_in_patch]]) {
    float u = patch_coord.x;
    float v = patch_coord.y;
    
    float2 top = mix(control_points[0].position.xz,
                     control_points[1].position.xz, u);
    float2 bottom = mix(control_points[3].position.xz,
                        control_points[2].position.xz, u);
    
    float2 interpolated = mix(top, bottom, v);
    
    float4 position = float4(interpolated.x, 0.0, interpolated.y, 1.0);
    float2 xz = (position.xz + terrain.size / 2.0) / terrain.size;
    position.y = terrain_height_noise(xz, terrain, heightMap, noiseMap);
    
    float eps = 0.05;
    
    float3 t_pos = position.xyz;
    
    float2 br = t_pos.xz + float2(eps, 0);
    float2 brz = (br + terrain.size / 2.0) / terrain.size;
    float hR = terrain_height_noise(brz, terrain, heightMap, noiseMap);
    
    float2 br2 = t_pos.xz + float2(-eps, 0);
    float2 brz2 = (br2 + terrain.size / 2.0) / terrain.size;
    float hL = terrain_height_noise(brz2, terrain, heightMap, noiseMap);
    
    float2 tl = t_pos.xz + float2(0, eps);
    float2 tlz = (tl + terrain.size / 2.0) / terrain.size;
    float hU = terrain_height_noise(tlz, terrain, heightMap, noiseMap);
    
    float2 tl2 = t_pos.xz + float2(0, -eps);
    float2 tlz2 = (tl2 + terrain.size / 2.0) / terrain.size;
    float hD = terrain_height_noise(tlz2, terrain, heightMap, noiseMap);
    
    float3 normal = float3(hL - hR, eps * 2, hD - hU);
    
    float4 clipPosition = uniforms.mvpMatrix * position;
    float3 worldPosition = position.xyz;
    float3 worldNormal = normal;
    
    return {
        .clipPosition = clipPosition,
        .worldPosition = worldPosition,
        .worldNormal = worldNormal
    };
}

fragment float4 eden_fragment(EdenVertexOut in [[stage_in]],
                              texture2d<float> texture [[texture(0)]]) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition);
    float3 c = texture.sample(repeat_sample, in.worldPosition.xz / 100).xyz;
    float3 c2 = texture.sample(repeat_sample, in.worldPosition.zx * 5).xyz / 20;
    N = N - c + c2;
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColour;// * c;
    return float4(finalColor, 1);
}
