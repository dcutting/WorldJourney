#include <metal_stdlib>
using namespace metal;

float3 quintic(float3 t)
{
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

constant float3 gradient_table[] = {
  float3(-0.299, 0.275, 0.268),
  float3(-0.857, -0.468, 0.316),
  float3(-0.028, -0.139, 0.567),
  float3(0.640, 0.183, -0.834),
  float3(0.155, -0.085, 0.753),
  float3(-0.408, -0.815, -0.154),
  float3(-0.646, -0.598, 0.615),
  float3(0.464, -0.988, -0.657),
  float3(0.452, 0.117, 0.642),
  float3(-0.098, -0.764, 0.187),
  float3(-0.942, 0.000, 0.071),
  float3(-0.272, -0.505, 0.288),
  float3(0.701, 0.520, 0.197),
  float3(-0.772, 0.347, -0.851),
  float3(0.357, -0.422, -0.665),
  float3(-0.071, 0.991, 0.287),
  float3(0.907, 0.725, -0.710),
  float3(-0.935, -0.583, 0.380),
  float3(-0.415, 0.045, -0.041),
  float3(-0.297, 0.623, -0.407)
};

float gradient_noise_inner(int3 cube_pos0, int3 cube_pos1, float3 t0, float3 t1)
{
    int x0 = cube_pos0.x;
    int y0 = cube_pos0.y;
    int z0 = cube_pos0.z;

    int x1 = cube_pos1.x;
    int y1 = cube_pos1.y;
    int z1 = cube_pos1.z;

    const int NOISE_HASH_X = 1213;
    const int NOISE_HASH_Y = 6203;
    const int NOISE_HASH_Z = 5237;
    const int NOISE_HASH_SEED = 1039;
    int ox0 = NOISE_HASH_X * x0 + NOISE_HASH_SEED;
    int oy0 = NOISE_HASH_Y * y0;
    int oz0 = NOISE_HASH_Z * z0;
    int ox1 = NOISE_HASH_X * x1 + NOISE_HASH_SEED;
    int oy1 = NOISE_HASH_Y * y1;
    int oz1 = NOISE_HASH_Z * z1;

    const int NOISE_HASH_SHIFT = 13;
    int index0 = ox0 + oy0 + oz0;
    int index1 = ox1 + oy0 + oz0;
    int index2 = ox0 + oy1 + oz0;
    int index3 = ox1 + oy1 + oz0;
    int index4 = ox0 + oy0 + oz1;
    int index5 = ox1 + oy0 + oz1;
    int index6 = ox0 + oy1 + oz1;
    int index7 = ox1 + oy1 + oz1;
    index0 ^= (index0 >> NOISE_HASH_SHIFT);
    index1 ^= (index1 >> NOISE_HASH_SHIFT);
    index2 ^= (index2 >> NOISE_HASH_SHIFT);
    index3 ^= (index3 >> NOISE_HASH_SHIFT);
    index4 ^= (index4 >> NOISE_HASH_SHIFT);
    index5 ^= (index5 >> NOISE_HASH_SHIFT);
    index6 ^= (index6 >> NOISE_HASH_SHIFT);
    index7 ^= (index7 >> NOISE_HASH_SHIFT);
    index0 &= 0xFF;
    index1 &= 0xFF;
    index2 &= 0xFF;
    index3 &= 0xFF;
    index4 &= 0xFF;
    index5 &= 0xFF;
    index6 &= 0xFF;
    index7 &= 0xFF;

    float3 grad0 = normalize(gradient_table[index0 % 20]); // TODO: fix with more gradients (not % 20)).
    float3 grad1 = normalize(gradient_table[index1 % 20]);
    float3 grad2 = normalize(gradient_table[index2 % 20]);
    float3 grad3 = normalize(gradient_table[index3 % 20]);
    float3 grad4 = normalize(gradient_table[index4 % 20]);
    float3 grad5 = normalize(gradient_table[index5 % 20]);
    float3 grad6 = normalize(gradient_table[index6 % 20]);
    float3 grad7 = normalize(gradient_table[index7 % 20]);

    // Project permuted fractionals onto gradient vector
    float4 g0246, g1357;
    g0246.x = dot(grad0, select(t0, t1, (bool3){ false, false, false }));
    g1357.x = dot(grad1, select(t0, t1, (bool3){ true, false, false }));
    g0246.y = dot(grad2, select(t0, t1, (bool3){ false, true, false }));
    g1357.y = dot(grad3, select(t0, t1, (bool3){ true, true, false }));
    g0246.z = dot(grad4, select(t0, t1, (bool3){ false, false, true }));
    g1357.z = dot(grad5, select(t0, t1, (bool3){ true, false, true }));
    g0246.w = dot(grad6, select(t0, t1, (bool3){ false, true, true }));
    g1357.w = dot(grad7, select(t0, t1, (bool3){ true, true, true }));

    float3 r = quintic(t0);
    float4 gx0123 = mix(g0246, g1357, r.x);
    float2 gy01 = mix(gx0123.xz, gx0123.yw, r.y);
    float gz = mix(gy01.x, gy01.y, r.z);

    return gz;
}
