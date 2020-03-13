#include <metal_stdlib>
using namespace metal;

float fbm(float, float, float, float, float, float);



// I/O.

struct ControlPoint {
    float4 position [[attribute(0)]];
};

struct PerPatchData {
    float2 r_a [[attribute(1)]];
};

struct PatchIn {
    PerPatchData patchData;
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

float4x4 rotate_x_4(float a) {
    return float4x4(1, 0, 0, 0,
                    0, cos(a), -sin(a), 0,
                    0, sin(a), cos(a), 0,
                    0, 0, 0, 1);
}

float4x4 rotate_y_4(float a) {
    return float4x4(cos(a), 0, sin(a), 0,
                    0, 1, 0, 0,
                    -sin(a), 0, cos(a), 0,
                    0, 0, 0, 1);
}

float f_height(float4 uvw, float frequency, float amplitude, float octaves) {
    float e = 1.0;
    float3 unit = normalize(uvw.xyz);
    float height = fbm(unit.x+e, unit.y+e, unit.z+e, frequency, amplitude/2, octaves) + amplitude/2;
    height = clamp(height, 0.0, amplitude);
    return height;
}

RasteriserData shared_vertex(float2 uvPosition, constant Uniforms &uniforms [[buffer(2)]], float2 r_a) {

    float r = uniforms.worldRadius;
    float f = uniforms.frequency;
    float a = uniforms.mountainHeight;
    float4x4 mm = uniforms.modelMatrix;
    
    float terrainOctaves = 150.0;
    float normalOctaves = 50.0;

    float4x4 ra_4 = rotate_x_4(r_a.x) * rotate_y_4(r_a.y);
    float4x4 ra_4m = ra_4 * mm;

    float u = uvPosition.x;
    float v = uvPosition.y;

    float s = u;
    float t = v;
    float h = f_height(float4(u,v,1,1)*ra_4, f, a, terrainOctaves) + 1.0;

    float w = sqrt(powr(s, 2.0) + powr(t, 2.0) + 1.0);

    float x = h*(s/w);
    float y = h*(t/w);
    float z = h*(1.0/w);

    /* Find normal. */
    
    float e = 0.02;
    //TODO: does this method make sense for top and bottom cube sides?
    float tuh = (f_height(float4(u+e, v, 1.0, 1)*ra_4, f, a, normalOctaves) - f_height(float4(u-e, v, 1.0, 1)*ra_4, f, a, normalOctaves))/(2.0*e);
    float tvh = (f_height(float4(u, v+e, 1.0, 1)*ra_4, f, a, normalOctaves) - f_height(float4(u, v-e, 1.0, 1)*ra_4, f, a, normalOctaves))/(2.0*e);
    float3 tu = float3(1.0, 0.0, tuh);
    float3 tv = float3(0.0, 1.0, tvh);

    // https://acko.net/blog/making-worlds-3-thats-no-moon/
    float w2 = powr(w, 2.0);
    float w3 = powr(w, 3.0);
    float s2 = powr(s, 2.0);
    float t2 = powr(t, 2.0);
    float3 ts = float3(h/w*(1-s2/w2), (-s*t*h)/w3, (-s*h)/w3);
    float3 tt = float3((-s*t*h)/w3, h/w*(1-t2/w2), (-t*h)/w3);
    float3 th = float3(s/w, t/w, 1.0/w);
    
    float3x3 Jsth = float3x3(ts, tt, th);
    
    float3 tpu = Jsth * tu;
    float3 tpv = Jsth * tv;

    float3 n = cross(tpu, tpv);
    
    float3 xyz = float3(x, y, z) * r;
    float4 worldPosition4 = float4(xyz,1) * ra_4m;
    float4 worldNormal = float4(n, 1) * ra_4m;

    /* Package up result. */
    
    float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition4;
    float3 colour = float3(1);

    RasteriserData data;
    data.clipPosition = clipPosition;
    data.worldPosition = worldPosition4;
    data.worldNormal = worldNormal.xyz;
    data.colour = colour;
    data.frameCounter = uniforms.frameCounter;
    return data;
}

vertex RasteriserData basic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                          constant Uniforms &uniforms [[buffer(2)]],
                                          unsigned int vid [[vertex_id]],
                                          texture3d<float> noise [[texture(0)]],
                                          sampler samplr [[sampler(0)]]) {

    float2 templatePosition = vertex_array[vid].xy;
    return shared_vertex(templatePosition, uniforms, 0);
}

// TODO: consider using quad patches since we're using quadtrees anyway.
[[patch(quad, 4)]]
vertex RasteriserData tessellation_vertex(PatchIn patchIn [[stage_in]],
                                          float2 patch_coord [[position_in_patch]],
                                          constant Uniforms &uniforms [[buffer(2)]],
                                          texture3d<float> noise [[texture(0)]],
                                          sampler samplr [[sampler(0)]]) {
    
    /* Find patch vertex. */
    
    float u = patch_coord.x;
    float v = patch_coord.y;

    float2 upper_middle = mix(patchIn.control_points[0].position.xy, patchIn.control_points[1].position.xy, u);
    float2 lower_middle = mix(patchIn.control_points[2].position.xy, patchIn.control_points[3].position.xy, 1-u);

    float2 modelPosition = mix(upper_middle, lower_middle, v);
    float2 r_a = patchIn.patchData.r_a;
    return shared_vertex(modelPosition, uniforms, r_a);
}



// Tesselation.

kernel void tessellation_kernel(constant float &tessellation_factor [[buffer(0)]],
                                device MTLQuadTessellationFactorsHalf *factors [[buffer(1)]],
                                uint pid [[thread_position_in_grid]]) {
    float insideTessellation = tessellation_factor;
    float edgeTessellation = insideTessellation;
    factors[pid].edgeTessellationFactor[0] = edgeTessellation;
    factors[pid].edgeTessellationFactor[1] = edgeTessellation;
    factors[pid].edgeTessellationFactor[2] = edgeTessellation;
    factors[pid].edgeTessellationFactor[3] = edgeTessellation;
    factors[pid].insideTessellationFactor[0] = insideTessellation;
    factors[pid].insideTessellationFactor[1] = insideTessellation;
}



// Fragment shader.

constant float3 ambientIntensity = 0.1;
constant float3 lightColor(0.8);

constant bool shaded = true;

fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    if (!shaded) {
        return float4(1.0);
    }
    
    float lightDistance = 5000;
    float cp = (float)in.frameCounter / 300;
    float x = lightDistance * cos(cp);
    float y = 0;
    float z = lightDistance * sin(cp);
    float3 lightWorldPosition = float3(x, y, z);

    float3 N = normalize(in.worldNormal);
    float3 L = normalize(lightWorldPosition - in.worldPosition.xyz);
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * lightColor * in.colour;
    return float4(finalColor, 1);
}
