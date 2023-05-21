#ifndef Maths_h
#define Maths_h

matrix_float4x4 scale(float scale);
matrix_float4x4 translate(vector_float3 translate);
matrix_float3x3 invertMatrix(matrix_float3x3 matrix);
matrix_float3x3 normalMatrix(matrix_float4x4 matrix);
float3 sphericalise_flat_gradient(float3 gradient, float amplitude, float3 surfacePoint);

#endif /* Maths_h */
