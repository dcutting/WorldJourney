#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 position [[position]];
    float4 colour;
} RasteriserData;

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 projectionMatrix;
};

vertex RasteriserData basic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   unsigned int vid [[vertex_id]]) {
    float4 v = float4(vertex_array[vid], 1.0);
    
    // Color corners.
    float4 c = float4(1.0, 0.0, 0.0, 1.0);
    if (v.y > 0.0) {
        c = float4(0.0, 0.0, 1.0, 1.0);
    } else if (v.x < 0.0) {
        c = float4(0.0, 1.0, 0.0, 1.0);
    }
    
    float4 projected = uniforms.projectionMatrix * uniforms.modelMatrix * v;
    
    return {
        projected,
        c
    };
}

fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    return in.colour;
}
