#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#ifndef Maths_h
#define Maths_h

float4x4 matrix_perspective(float fovyRadians, float aspect, float nearZ, float farZ);
float4x4 matrix_translate(float3 t);
float4x4 matrix_rotate(float radians, float3 axis);
matrix_float4x4 scale(float scale);
matrix_float4x4 translate(vector_float3 translate);
matrix_float3x3 invertMatrix(matrix_float3x3 matrix);
matrix_float3x3 normalMatrix(matrix_float4x4 matrix);
float3 sphericalise_flat_gradient(float3 gradient, float amplitude, float3 surfacePoint);
float adaptiveOctaves(float dist, int minOctaves, int maxOctaves, float minDist, float maxDist, float p);

#endif /* Maths_h */
