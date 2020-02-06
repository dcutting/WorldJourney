#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 position [[position]];
    float4 colour;
} RasteriserData;

vertex RasteriserData basic_vertex(const device packed_float3* vertex_array [[buffer(0)]], unsigned int vid [[vertex_id]]) {
    float3 v = vertex_array[vid];
    float4 c = float4(1.0, 0.0, 0.0, 1.0);
    if (v.x < 0.0) {
        c = float4(0.0, 1.0, 0.0, 1.0);
    }
    return {
        float4(v, 1.0),
        c
    };
}

fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    return in.colour;
}
