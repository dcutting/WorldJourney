#ifndef Maths_h
#define Maths_h

matrix_float4x4 scale(float scale);
matrix_float4x4 translate(vector_float3 translate);
matrix_float3x3 invertMatrix(matrix_float3x3 matrix);
matrix_float3x3 normalMatrix(matrix_float4x4 matrix);

#endif /* Maths_h */
