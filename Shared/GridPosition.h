#ifndef GridPosition_h
#define GridPosition_h

typedef struct {
  int3 i;
  float3 f;
} GridPosition;

GridPosition addGridPosition(GridPosition a, GridPosition b);

GridPosition multiplyGridPosition(GridPosition a, float m);

GridPosition makeGridPosition(float3 a);

GridPosition makeGridPosition(int3 i, float3 f);

GridPosition makeGridPosition(int3 cubeOrigin, int cubeSize, float3 x);

//GridPosition rotateGridPosition(GridPosition a, float theta);

GridPosition getX(GridPosition p);

GridPosition getY(GridPosition p);

GridPosition getZ(GridPosition p);

#endif
