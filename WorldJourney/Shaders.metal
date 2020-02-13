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
//    return 1.0;
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
    
    float3 b = float3(0, 0.1002310, 0.937189); // TODO: this has to be linearly independent of eye.
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

RasteriserData terrain_vertex(float3 templatePosition, constant Uniforms &uniforms) {
    float r = uniforms.worldRadius;
    float R = r + uniforms.amplitude;
    float f = uniforms.frequency;
    float a = uniforms.amplitude;
    float3 eye = uniforms.cameraPosition;
    float4x4 mm = uniforms.modelMatrix;
    float d = length(eye);

    float3 v = find_terrain_for_template(templatePosition, r, R, d, f, a, eye, mm);

    float offsetDelta = 0.0374576271;//uniforms.gridWidth; // TODO
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

vertex RasteriserData michelic_vertex(const device packed_float3 *vertex_array [[buffer(0)]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      unsigned int vid [[vertex_id]]) {

    float3 templatePosition = vertex_array[vid];
    return terrain_vertex(templatePosition, uniforms);
}

kernel void tessellation_kernel(constant float &distance [[buffer(0)]],
                                device MTLTriangleTessellationFactorsHalf *factors [[buffer(1)]],
                                uint pid [[thread_position_in_grid]]) {
    float tessellation = 64/distance;
    factors[pid].edgeTessellationFactor[0] = tessellation;
    factors[pid].edgeTessellationFactor[1] = tessellation;
    factors[pid].edgeTessellationFactor[2] = tessellation;
    factors[pid].insideTessellationFactor = tessellation;
}

struct ControlPoint {
    float4 position [[attribute(0)]];
};

struct PatchIn {
    patch_control_point<ControlPoint> control_points;
};

[[patch(triangle, 3)]]
vertex RasteriserData tessellation_vertex(PatchIn patchIn [[stage_in]],
                                          float3 patch_coord [[position_in_patch]],
                                          constant Uniforms &uniforms [[buffer(1)]]) {
    float u = patch_coord.x;
    float v = patch_coord.y;
    float w = patch_coord.z;
    
    float x = u * patchIn.control_points[0].position.x + v * patchIn.control_points[1].position.x + w * patchIn.control_points[2].position.x;
    
    float y = u * patchIn.control_points[0].position.y + v * patchIn.control_points[1].position.y + w * patchIn.control_points[2].position.y;
    
    float3 templatePosition = float3(x, y, 0);
    return terrain_vertex(templatePosition, uniforms);
}
