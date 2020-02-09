#include <metal_stdlib>
using namespace metal;

float fbm(float, float, float, float, float);

typedef struct {
    float4 clipPosition [[position]];
    float4 worldPosition;
    float3 worldNormal;
    float3 colour;
} RasteriserData;

struct Uniforms {
    float cameraDistance;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float4x4 projectionMatrix;
};

float find_height(float2 p) {
    return fbm(p.x, p.y, 0.0, 0.01, 10);
}

float find_height(float3 p, float r, float R) {
    float3 q = p + float3(2.0);
    return fbm(q.x, q.y, q.z, 0.5, R - r);
}

float3 find_model_normal(float4 modelPosition) {
    float offsetDelta = 1.0;
    float3 off = float3(offsetDelta, offsetDelta, 0.0);
    float hL = find_height(modelPosition.xy - off.xz);
    float hR = find_height(modelPosition.xy + off.xz);
    float hD = find_height(modelPosition.xy - off.zy);
    float hU = find_height(modelPosition.xy + off.zy);
    float3 modelNormal = float3(hL - hR, hD - hU, 2 * offsetDelta);
    return modelNormal;
}

float3 model_normal_to_world(float3 modelNormal, float4x4 modelMatrix) {
    float3 worldNormal = (modelMatrix * float4(modelNormal, 0.0)).xyz;
    worldNormal = normalize(worldNormal);
    return worldNormal;
}

vertex RasteriserData basic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   unsigned int vid [[vertex_id]]) {
    float3 templatePosition = vertex_array[vid];
    float height = find_height(templatePosition.xy);
    float4 modelPosition = float4(templatePosition.xy, height, 1.0);
    float3 modelNormal = find_model_normal(modelPosition);
    float4 worldPosition = uniforms.modelMatrix * modelPosition;
    float3 worldNormal = model_normal_to_world(modelNormal, uniforms.modelMatrix);
    float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    float3 colour = float3(0.5, 0.5, 0.5);

    RasteriserData data;
    data.clipPosition = clipPosition;
    data.worldPosition = worldPosition;
    data.worldNormal = worldNormal;
    data.colour = colour;
    return data;
}

constant float3 ambientIntensity = 1.0;
constant float3 lightWorldPosition(200, 200, 200);
constant float3 lightColor(1, 1, 1);
 
fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition.xyz);
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColor * in.colour;
    return float4(finalColor, 1);
}

constant float worldRadius = 2.0;

vertex RasteriserData michelic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   unsigned int vid [[vertex_id]]) {
    float3 templatePosition = vertex_array[vid];
    
    float d = uniforms.cameraDistance;
    float r = worldRadius;
    float maxMountainHeight = r * 0.1;
    float R = worldRadius + maxMountainHeight;
    
    float h = sqrt(powr(d, 2) - powr(r, 2));
    float s = sqrt(powr(R, 2) - powr(r, 2));
    
    float zs = (powr(R, 2) + powr(d, 2) - powr(h+s, 2)) / (2 * r * (h+s));
    
    float3 z = float3(0.0, 0.0, zs);
    float3 g = templatePosition;
    float n = 4;
    g.z = (1 - powr(g.x, n)) * (1 - powr(g.y, n));
    float3 gp = g + z;
    float mg = length(gp);
    float3 vector = g / mg;
    float raw_height = find_height(vector * r, r, R);
    float height = raw_height / 1.0;
    float altitude = r + height;
    float3 v = vector * altitude;

    float4 modelPosition = float4(v, 1.0);
    float3 modelNormal = find_model_normal(modelPosition);
    float4 worldPosition = uniforms.modelMatrix * modelPosition;
    float3 worldNormal = model_normal_to_world(modelNormal, uniforms.modelMatrix);
    float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    float3 colour = float3(0.5, 0.5, 0.5);

    RasteriserData data;
    data.clipPosition = clipPosition;
    data.worldPosition = worldPosition;
    data.worldNormal = worldNormal;
    data.colour = colour;
    return data;
}
