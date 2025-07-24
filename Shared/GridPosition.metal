#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#include "GridPosition.h"

GridPosition addGridPosition(GridPosition a, GridPosition b) {
  GridPosition r;
  float3 f = a.f + b.f;
  r.i = a.i + b.i + (int3)floor(f);
  r.f = fract(f);
  return r;
}

GridPosition multiplyGridPosition(GridPosition a, float m) {
  GridPosition r;
  // E.g., 3.8 * 2.4 = 9.12
  float3 im = (float3)a.i * m;  // 3 * 2.4 = 7.2
  float3 fm = a.f * m; // 1.92
  float3 ifm = fract(im) + fract(fm); // 0.2 + 0.92 = 1.12
  r.i = (int3)floor(im) + (int3)floor(fm) + (int3)floor(ifm); // 7 + 1 + 1 = 9
  r.f = fract(ifm); // 0.12
  return r;
}

GridPosition makeGridPosition(float3 a) {
  return { (int3)floor(a), fract(a) };
}

GridPosition makeGridPosition(int3 i, float3 f) {
  return addGridPosition({i, 0}, makeGridPosition(f));
}

GridPosition makeGridPosition(int3 cubeOrigin, int cubeSize, float3 x) {
  GridPosition origin = { cubeOrigin, 0 };
  GridPosition offset = makeGridPosition(x * cubeSize);
  GridPosition initial = addGridPosition(origin, offset);
  return initial;
}

//GridPosition rotateGridPosition(GridPosition a, float theta) {
//  float ct = cos(theta);
//  float st = sin(theta);
//
//  float xi = (float)a.i.x;
//  float zi = (float)a.i.z;
//  float xit = xi * ct - zi * st;
//  float zit = xi * st + zi * ct;
//  int3 it = int3(xit, 0, zit);
//  GridPosition i = { it, 0 };
//
//  float xf = a.f.x;
//  float zf = a.f.z;
//  float xft = xf * ct - zf * st;
//  float zft = xf * st + zf * ct;
//  float3 ft = float3(xft, 0, zft);
//
//  GridPosition f = makeGridPosition(ft);
//
//  return addGridPosition(i, f);
//}

GridPosition getX(GridPosition p) {
  return makeGridPosition(int3(p.i.x, 0, 0), float3(p.f.x, 0, 0));
}

GridPosition getY(GridPosition p) {
  return makeGridPosition(int3(p.i.y, 0, 0), float3(p.f.y, 0, 0));
}

GridPosition getZ(GridPosition p) {
  return makeGridPosition(int3(p.i.z, 0, 0), float3(p.f.z, 0, 0));
}
