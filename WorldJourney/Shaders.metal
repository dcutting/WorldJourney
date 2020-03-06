#include <metal_stdlib>
using namespace metal;

float fbm(float, float, float, float, float);



// I/O.

struct ControlPoint {
    float4 position [[attribute(0)]];
};

struct PatchIn {
    patch_control_point<ControlPoint> control_points;
};

typedef struct {
    float4 clipPosition [[position]];
    float4 worldPosition;
    float3 worldNormal;
    float3 colour;
} RasteriserData;

struct Uniforms {
    float worldRadius;
    float frequency;
    float mountainHeight;
    short gridWidth;
    float3 cameraPosition;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float4x4 projectionMatrix;
};



// Vertex shader.

float find_height_for_spherical(float3 p, float r, float frequency, float amplitude) {
    float3 q = p + float3(r*2); // need to offset because the noise function seems not to be continuous around 0 or negative values.
    float height = fbm(q.x, q.y, q.z, frequency, amplitude/2) + amplitude/2;
    height = clamp(height, 0.0, amplitude);
    return height;
}

// Must return a value between 0 and a.
float3 find_terrain_position(float3 p, float r, float f, float maxHeight, float4x4 modelMatrix, texture3d<float> noise, sampler samplr) {
//    return p * r/2;
    float3 unit_spherical = normalize(p);
    float4 modelled = float4(unit_spherical * r, 1) * transpose(modelMatrix);
    float height = find_height_for_spherical(modelled.xyz, r, f, maxHeight);
    float altitude = r + height;
    float3 v = unit_spherical * altitude;
    return v;
}

float3x3 rotate_x(float a) {
    return float3x3(1, 0, 0,
                    0, cos(a), -sin(a),
                    0, sin(a), cos(a));
}

float3x3 rotate_y(float a) {
    return float3x3(cos(a), 0, sin(a),
                    0, 1, 0,
                    -sin(a), 0, cos(a));
}

[[patch(triangle, 3)]]
vertex RasteriserData tessellation_vertex(PatchIn patchIn [[stage_in]],
                                          float3 patch_coord [[position_in_patch]],
                                          constant Uniforms &uniforms [[buffer(1)]],
                                          texture3d<float> noise [[texture(0)]],
                                          sampler samplr [[sampler(0)]]) {
    
    float r = uniforms.worldRadius;
    float f = uniforms.frequency;
    float maxHeight = uniforms.mountainHeight;
    float4x4 mm = uniforms.modelMatrix;

    /* Find patch vertex. */
    
    float u = patch_coord.x;
    float v = patch_coord.y;
    float w = patch_coord.z;
    float x = u * patchIn.control_points[0].position.x + v * patchIn.control_points[1].position.x + w * patchIn.control_points[2].position.x;
    float y = u * patchIn.control_points[0].position.y + v * patchIn.control_points[1].position.y + w * patchIn.control_points[2].position.y;
    float z = u * patchIn.control_points[0].position.z + v * patchIn.control_points[1].position.z + w * patchIn.control_points[2].position.z;
    float3 modelPosition = float3(x, y, z);
    
    /* Find position on rotated sphere. */

    float3 _worldPosition = (float4(modelPosition, 1) * mm).xyz;
    float3 worldPosition = find_terrain_position(_worldPosition, r, f, maxHeight, mm, noise, samplr);
    
    /* Find normal. */
    
    float offset = 1;
//    float3 vL = find_terrain_for_template(vtx * rotate_y(offset), r, f, maxHeight, mm, noise, samplr);
//    float3 vR = find_terrain_for_template(vtx * rotate_y(-offset), r, f, maxHeight, mm, noise, samplr);
//    float3 vD = find_terrain_for_template(vtx * rotate_x(offset), r, f, maxHeight, mm, noise, samplr);
//    float3 vU = find_terrain_for_template(vtx * rotate_x(-offset), r, f, maxHeight, mm, noise, samplr);
//    float3 dLR = vR - vL;
//    float3 dDU = vD - vU;
//    float3 worldNormal = cross(dLR, dDU);

    float3 off = float3(offset, offset, 0.0);
    float hL = find_height_for_spherical(float3(worldPosition.xy - off.xz, worldPosition.z), r, f, maxHeight);
    float hR = find_height_for_spherical(float3(worldPosition.xy + off.xz, worldPosition.z), r, f, maxHeight);
    float hD = find_height_for_spherical(float3(worldPosition.xy - off.zy, worldPosition.z), r, f, maxHeight);
    float hU = find_height_for_spherical(float3(worldPosition.xy + off.zy, worldPosition.z), r, f, maxHeight);

//    float3 vL = find_terrain_for_template(float3(vtx.xy - off.xz, vtx.z), r, f, maxHeight, mm, noise, samplr);
//    float3 vR = find_terrain_for_template(float3(vtx.xy + off.xz, vtx.z), r, f, maxHeight, mm, noise, samplr);
//    float3 vD = find_terrain_for_template(float3(vtx.xy - off.zy, vtx.z), r, f, maxHeight, mm, noise, samplr);
//    float3 vU = find_terrain_for_template(float3(vtx.xy + off.zy, vtx.z), r, f, maxHeight, mm, noise, samplr);
//    float3 worldNormal = float3(hL - hR, hD - hU, 2 * offset);

    float3 worldNormal = worldPosition;

    /* Package up result. */
    
    float4 worldPosition4 = float4(worldPosition, 1.0);
    float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition4;
    float3 colour = float3(0.7);

    RasteriserData data;
    data.clipPosition = clipPosition;
    data.worldPosition = worldPosition4;
    data.worldNormal = worldNormal;
    data.colour = colour;
    return data;
}



// Tesselation.

kernel void tessellation_kernel(constant float &tessellation_factor [[buffer(0)]],
                                device MTLTriangleTessellationFactorsHalf *factors [[buffer(1)]],
                                uint pid [[thread_position_in_grid]]) {
    float insideTessellation = tessellation_factor;
    float edgeTessellation = insideTessellation;
    factors[pid].edgeTessellationFactor[0] = edgeTessellation;
    factors[pid].edgeTessellationFactor[1] = edgeTessellation;
    factors[pid].edgeTessellationFactor[2] = edgeTessellation;
    factors[pid].insideTessellationFactor = insideTessellation;
}



// Fragment shader.

constant float3 ambientIntensity = 0.02;
constant float3 lightWorldPosition(50000, 50000, 50000);
constant float3 lightColor(1.0, 1.0, 1.0);

constant bool shaded = true;

fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    if (!shaded) {
        return float4(1.0);
    }
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition.xyz);
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColor * in.colour;
    return float4(finalColor, 1);
}
