#include "Maths.h"

float4x4 matrix_perspective(float fovyRadians, float aspect, float nearZ, float farZ) {
  float ys = 1 / tan(fovyRadians * 0.5);
  float xs = ys / aspect;
  float zs = farZ / (nearZ - farZ);
  
  return float4x4((float4){ xs, 0, 0, 0 },
                  (float4){ 0, ys, 0, 0 },
                  (float4){ 0, 0, zs, -1 },
                  (float4){ 0, 0, nearZ * zs, 0 });
}

float4x4 matrix_translate(float3 t) {
  return float4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, t[0], t[1], t[2], 1);
}

float4x4 matrix_rotate(float radians, float3 axis) {
  auto unitAxis = normalize(axis);
  auto ct = cos(radians);
  auto st = sin(radians);
  auto ci = 1 - ct;
  auto x = unitAxis.x, y = unitAxis.y, z = unitAxis.z;
  return float4x4(float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                  float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                  float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                  float4(                  0,                   0,                   0, 1));
}
