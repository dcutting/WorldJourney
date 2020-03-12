#include <metal_stdlib>
using namespace metal;

float fbm(float, float, float, float, float, float);



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
    short frameCounter;
} RasteriserData;

struct Uniforms {
    float worldRadius;
    float frequency;
    float mountainHeight;
    short frameCounter;
    float3 cameraPosition;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float4x4 projectionMatrix;
};



// Vertex shader.

//float find_height_for_spherical(float3 p, float r, float frequency, float amplitude, float octaves) {
//    float3 q = p + float3(r*2); // need to offset because the noise function seems not to be continuous around 0 or negative values.
//    float height = fbm(q.x, q.y, q.z, frequency, amplitude/2, octaves) + amplitude/2;
//    height = clamp(height, 0.0, amplitude);
//    return height;
//}

// Must return a value between 0 and a.
//float3 find_terrain_position(float3 p, float r, float f, float maxHeight, float4x4 modelMatrix, texture3d<float> noise, sampler samplr) {
////    return p * r/2;
//    float3 unit_spherical = normalize(p);
//    float4 modelled = float4(unit_spherical * r, 1) * transpose(modelMatrix);
//    float height = find_height_for_spherical(modelled.xyz, r, f, maxHeight);
//    float altitude = r + height;
//    float3 v = unit_spherical * altitude;
//    return v;
//}

//float3x3 rotate_x(float a) {
//    return float3x3(1, 0, 0,
//                    0, cos(a), -sin(a),
//                    0, sin(a), cos(a));
//}
//
//float3x3 rotate_y(float a) {
//    return float3x3(cos(a), 0, sin(a),
//                    0, 1, 0,
//                    -sin(a), 0, cos(a));
//}

float f_height(float u, float v, float w, float frequency, float amplitude, float octaves) {
    float e = 1;
    float height = fbm(u+e, v+e, w+e, frequency, amplitude/2, octaves) + amplitude/2;
    height = clamp(height, 0.0, amplitude);
    return height;
}

float3 pos_at(float x, float y, float z, float f, float a, float o, float r) {
    float3 unit = normalize(float3(x, y, z));
    float h = f_height(unit.x, unit.y, unit.z, f, a, o);
    float3 xyz = unit * (r * (1+h));
    return xyz;
}

RasteriserData shared_vertex(float3 modelPosition, constant Uniforms &uniforms [[buffer(1)]]) {

        float r = uniforms.worldRadius;
    //    float f = uniforms.frequency;
    //    float maxHeight = uniforms.mountainHeight;
    //    float4x4 mm = uniforms.modelMatrix;

//    modelPosition = (mm * float4(modelPosition, 1)).xyz;
    
    /* Find position on rotated sphere. */

//    float3 _worldPosition = (float4(modelPosition, 1) * mm).xyz;
//    float3 worldPosition = find_terrain_position(_worldPosition, r, f, maxHeight, mm, noise, samplr);
    
    float f = 5;
    float a = 0.06;
    float terrainOctaves = 200.0;
    float normalOctaves = 20.0f;

#if 0
    
    float x_m = modelPosition.x;
    float y_m = modelPosition.y;
    float z_m = modelPosition.z;
    
    float3 xyz = pos_at(x_m, y_m, z_m, f, a, terrainOctaves, r);

    float e = 0.01;
    float3 tu1 = pos_at(x_m - e, y_m, z_m, f, a, normalOctaves, 1);
    float3 tu2 = pos_at(x_m + e, y_m, z_m, f, a, normalOctaves, 1);
    float tuh = (length(tu1) - length(tu2)) / (2*e);
    float3 tv1 = pos_at(x_m, y_m - e, z_m, f, a, normalOctaves, 1);
    float3 tv2 = pos_at(x_m, y_m + e, z_m, f, a, normalOctaves, 1);
    float tvh = (length(tv1) - length(tv2)) / (2*e);
    float3 tu = float3((normalize(tu1).x-normalize(tu1).x), 0, tuh);
    float3 tv = float3(0, normalize(tv1).y-normalize(tv2).y, tvh);
    float3 n = cross(tu, tv);

#else
    
    float u = modelPosition.x;
    float v = modelPosition.y;
    float zz = modelPosition.z;

    float s = u;
    float t = v;
    float h = f_height(u, v, 1.0, f, a, terrainOctaves) + zz;

    float w = length(float3(s, t, zz));

    float x = h*s/w;
    float y = h*t/w;
    float z = h*1/w;

    float3 xyz = float3(x, y, z) * r;

//    float3 n = xyz;

    /* Find normal. */
    
    float e = 0.01;//03;
    float tuh = (f_height(u+e, v, 1.0, f, a, normalOctaves) - f_height(u-e, v, 1.0, f, a, normalOctaves))/(2*e);
    float tvh = (f_height(u, v+e, 1.0, f, a, normalOctaves) - f_height(u, v-e, 1.0, f, a, normalOctaves))/(2*e);
    float3 tu = float3(1, 0, tuh);
    float3 tv = float3(0, 1, tvh);

    // https://acko.net/blog/making-worlds-3-thats-no-moon/
//    float w2 = pow(w, 2);
//    float w3 = pow(w, 3);
//    float s2 = pow(s, 2);
//    float t2 = pow(t, 2);
//    float3 ts = float3(h/w*(1-s2/w2), -s*t*h/w3, -s*h/w3);
//    float3 tt = float3(-s*t*h/w3, h/w*(1-t2/w2), -t*h/w3);
//    float3 th = float3(s/w, t/w, 1/w);
    
    // https://community.khronos.org/t/need-help-normal-mapping-a-cube-mapped-sphere/73501/6
    float3 ts = float3(w, 0, s/w);
    float3 tt = float3(0, w, t/w);
    float3 th = float3(-s/w, -t/w, 1/w);

    float3x3 Jsth = transpose(float3x3(ts, tt, th));
    float3 tpu = Jsth * tu;
    float3 tpv = Jsth * tv;
    float3 n = cross(tpu, tpv);
#endif
    
    /* Package up result. */
    
//    float4 worldPosition4 = float4(x*r, y*r, z*r, 1.0);
    float4 worldPosition4 = float4(xyz, 1.0);
//    float4 worldPosition4 = float4(modelPosition*r, 1.0);
//    float3 worldNormal = float3(0, 0, 1);
    float3 worldNormal = n;
//    float3 worldNormal = modelPosition;
    float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition4;
    float3 colour = float3(1.0);

    RasteriserData data;
    data.clipPosition = clipPosition;
    data.worldPosition = worldPosition4;
    data.worldNormal = worldNormal;
    data.colour = colour;
    data.frameCounter = uniforms.frameCounter;
    return data;
}

vertex RasteriserData basic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                          constant Uniforms &uniforms [[buffer(1)]],
                                          unsigned int vid [[vertex_id]],
                                          texture3d<float> noise [[texture(0)]],
                                          sampler samplr [[sampler(0)]]) {

    float3 templatePosition = vertex_array[vid];
    return shared_vertex(templatePosition, uniforms);
}

[[patch(triangle, 3)]]
vertex RasteriserData tessellation_vertex(PatchIn patchIn [[stage_in]],
                                          float3 patch_coord [[position_in_patch]],
                                          constant Uniforms &uniforms [[buffer(1)]],
                                          texture3d<float> noise [[texture(0)]],
                                          sampler samplr [[sampler(0)]]) {
    
    /* Find patch vertex. */
    
    float u_p = patch_coord.x;
    float v_p = patch_coord.y;
    float w_p = patch_coord.z;
    float x_m = u_p * patchIn.control_points[0].position.x + v_p * patchIn.control_points[1].position.x + w_p * patchIn.control_points[2].position.x;
    float y_m = u_p * patchIn.control_points[0].position.y + v_p * patchIn.control_points[1].position.y + w_p * patchIn.control_points[2].position.y;
    float z_m = u_p * patchIn.control_points[0].position.z + v_p * patchIn.control_points[1].position.z + w_p * patchIn.control_points[2].position.z;
    float3 modelPosition = float3(x_m, y_m, z_m);
    return shared_vertex(modelPosition, uniforms);
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

constant float3 ambientIntensity = 0.05;
constant float3 lightColor(1.0, 1.0, 1.0);

constant bool shaded = true;

fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    if (!shaded) {
        return float4(1.0);
    }
    
    float lightDistance = 5000;
    float cp = (float)in.frameCounter / 100;// - 500000;
    float x = lightDistance * cos(cp);
    float y = 0;//lightDistance;
    float z = lightDistance * sin(cp);
    float3 lightWorldPosition = float3(x, y, z);
//    float3 lightWorldPosition = float3(lightDistance, lightDistance, 0);

    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition.xyz);
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColor * in.colour;
    return float4(finalColor, 1);
}
