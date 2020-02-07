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

// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

vertex RasteriserData basic_vertex(const device packed_float3* vertex_array [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   unsigned int vid [[vertex_id]]) {
    float3 vo = vertex_array[vid];
    vo += rand(vo.x, vo.y, vo.z) / 2;

    float4 v = float4(vo, 1.0);
        
    // Color corners.
    float4 c = float4(1.0, 0.0, 0.0, 1.0);
    if (vid % 2 == 0) {
        c = float4(0.0, 0.0, 1.0, 1.0);
    }
//    if (v.y > 0.0) {
//        c = float4(0.0, 0.0, 1.0, 1.0);
//    } else if (v.x < 0.0) {
//        c = float4(0.0, 1.0, 0.0, 1.0);
//    }
    
    float4 projected = uniforms.projectionMatrix * uniforms.modelMatrix * v;
    
    return {
        projected,
        c
    };
}

fragment float4 basic_fragment(RasteriserData in [[stage_in]]) {
    return in.colour;
}
