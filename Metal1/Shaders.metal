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
    float worldRadius;
    float frequency;
    float amplitude;
    short gridWidth;
    float3 cameraPosition;
    float cameraDistance;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float4x4 projectionMatrix;
};

float find_height_for_spherical(float3 p, float r, float frequency, float amplitude) {
    float3 q = p + float3(r);
    return fbm(q.x, q.y, q.z, frequency, amplitude);
}

constant float3 ambientIntensity = 0.02;
constant float3 lightWorldPosition(200, 200, 50);
constant float3 lightColor(1.0, 1.0, 1.0);
 
fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition.xyz);
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColor * in.colour;
    return float4(finalColor, 1);
}

float3 find_unit_spherical_for_template(float3 p, float r, float R, float d, float3 eye) {
    float h = sqrt(powr(d, 2) - powr(r, 2));
    float s = sqrt(powr(R, 2) - powr(r, 2));
    
    float zs = (powr(R, 2) + powr(d, 2) - powr(h+s, 2)) / (2 * r * (h+s));
    
    float3 z = float3(0.0, 0.0, zs);
    float3 g = p;
    float n = 4;
    g.z = (1 - powr(g.x, n)) * (1 - powr(g.y, n));
    float3 gp = g + z;
    float mgp = length(gp);
    float3 vector = gp / mgp;
    
    float3 b = float3(0, 0.1002310, 0.937189); // TODO: this has to be independent of eye.
    float3 w = eye / length(eye);
    float3 wb = cross(w, b);
    float3 v = wb / length(wb);
    float3 u = cross(w, v);
    float3x3 rotation = transpose(float3x3(u, v, w));
    
    float3 rotated = vector * rotation;
    return rotated;
}

float3 find_terrain_for_template(float3 p, float r, float R, float d, float f, float a, float3 eye, float4x4 modelMatrix) {
    float3 unit_spherical = find_unit_spherical_for_template(p, r, R, d, eye);
    float4 modelled = float4(unit_spherical * r, 1) * modelMatrix;
    float height = find_height_for_spherical(modelled.xyz, r, f, a);
    float altitude = r + height;
    float3 v = unit_spherical * altitude;
    return v;
}

vertex RasteriserData michelic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      unsigned int vid [[vertex_id]]) {

    float3 templatePosition = vertex_array[vid];
    float d = uniforms.cameraDistance;
    float r = uniforms.worldRadius;
    float R = r + uniforms.amplitude;
    float f = uniforms.frequency;
    float a = uniforms.amplitude;
    float3 eye = uniforms.cameraPosition;
    float4x4 mm = uniforms.modelMatrix;
    
    float3 v = find_terrain_for_template(templatePosition, r, R, d, f, a, eye, mm);

    float offsetDelta = 1.0/uniforms.gridWidth;
    float3 off = float3(offsetDelta, offsetDelta, 0.0);
    float3 vL = find_terrain_for_template(float3(templatePosition.xy - off.xz, 0.0), r, R, d, f, a, eye, mm);
    float3 vR = find_terrain_for_template(float3(templatePosition.xy + off.xz, 0.0), r, R, d, f, a, eye, mm);
    float3 vD = find_terrain_for_template(float3(templatePosition.xy - off.zy, 0.0), r, R, d, f, a, eye, mm);
    float3 vU = find_terrain_for_template(float3(templatePosition.xy + off.zy, 0.0), r, R, d, f, a, eye, mm);

    float3 dLR = vR - vL;
    float3 dDU = vD - vU;
    float3 worldNormal = cross(dLR, dDU);
    float4 worldPosition = float4(v, 1.0);
    float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    float3 colour = float3(1.0, 1.0, 1.0);

    RasteriserData data;
    data.clipPosition = clipPosition;
    data.worldPosition = worldPosition;
    data.worldNormal = worldNormal;
    data.colour = colour;
    return data;
}
