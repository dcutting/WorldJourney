#include <metal_stdlib>
using namespace metal;

#ifndef Maths_h
#define Maths_h

float4x4 matrix_perspective(float fovyRadians, float aspect, float nearZ, float farZ);
float4x4 matrix_translate(float3 t);
float4x4 matrix_rotate(float radians, float3 axis);

#endif /* Maths_h */
