#include <metal_stdlib>
#include "Common.h"
using namespace metal;

//  init(scaleByX x: Float, y: Float, z: Float) {
//    self.init(SIMD4<Float>(x, 0, 0, 0),
//              SIMD4<Float>(0, y, 0, 0),
//              SIMD4<Float>(0, 0, z, 0),
//              SIMD4<Float>(0, 0, 0, 1))
//  }
//
matrix_float4x4 scale(float s) {
  return matrix_float4x4(s,0,0,0, 0,s,0,0, 0,0,s,0, 0,0,0,1);
}

//  init(translationBy t: SIMD3<Float>) {
//    self.init(SIMD4<Float>(   1,    0,    0, 0),
//              SIMD4<Float>(   0,    1,    0, 0),
//              SIMD4<Float>(   0,    0,    1, 0),
//              SIMD4<Float>(t[0], t[1], t[2], 1))
//  }
matrix_float4x4 translate(vector_float3 t) {
  return matrix_float4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, t[0], t[1], t[2], 1);
}

// TODO: check maths.
matrix_float3x3 invertMatrix(matrix_float3x3 matrix) {
  float3 x0(matrix[0][0], matrix[1][0], matrix[2][0]);
  float3 x1(matrix[0][1], matrix[1][1], matrix[2][1]);
  float3 x2(matrix[0][2], matrix[1][2], matrix[2][2]);
  matrix_float3x3 upperLeft(x0, x1, x2);
  float det = determinant(upperLeft);
  float3 x1x2 = cross(x1, x2);
  float3 x2x0 = cross(x2, x0);
  float3 x0x1 = cross(x0, x1);
  return 1.0/det * matrix_float3x3(x1x2, x2x0, x0x1);
}

// TODO-DC: check maths.
matrix_float3x3 normalMatrix(matrix_float4x4 matrix) {
  float3 x0(matrix[0][0], matrix[1][0], matrix[2][0]);
  float3 x1(matrix[0][1], matrix[1][1], matrix[2][1]);
  float3 x2(matrix[0][2], matrix[1][2], matrix[2][2]);
  matrix_float3x3 upperLeft(x0, x1, x2);
  return transpose(invertMatrix(transpose(upperLeft)));
}

//  init(rotationAbout axis: SIMD3<Float>, by angleRadians: Float) {
//    let x = axis.x, y = axis.y, z = axis.z
//    let c = cosf(angleRadians)
//    let s = sinf(angleRadians)
//    let t = 1 - c
//    self.init(SIMD4<Float>( t * x * x + c,     t * x * y + z * s, t * x * z - y * s, 0),
//              SIMD4<Float>( t * x * y - z * s, t * y * y + c,     t * y * z + x * s, 0),
//              SIMD4<Float>( t * x * z + y * s, t * y * z - x * s,     t * z * z + c, 0),
//              SIMD4<Float>(                 0,                 0,                 0, 1))
//  }

float3 sphericalise_flat_gradient(float3 gradient, float amplitude, float3 unitSurfacePoint) {
  // https://math.stackexchange.com/questions/1071662/surface-normal-to-point-on-displaced-sphere
  // https://www.physicsforums.com/threads/why-is-the-gradient-vector-normal-to-the-level-surface.527567/
  float3 h = gradient - (dot(gradient, unitSurfacePoint) * unitSurfacePoint);
  float3 n = unitSurfacePoint - (amplitude * h);
  return normalize(n);
}

float adaptiveOctaves(float dist, int minOctaves, int maxOctaves, float minDist, float maxDist, float p) {
  float i = dist;
  float A = maxDist;
  float B = minDist;
  float N = A - B;
  float v2 = i / N;
  v2 = pow(v2, p);

  float factor = saturate(v2);

  float detailFactor = 1.0 - (factor * 0.99 + 0.001);

  float fractOctaves = ((float)maxOctaves - (float)minOctaves) * detailFactor + (float)minOctaves;
  
  return fractOctaves;
}
