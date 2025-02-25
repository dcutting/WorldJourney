#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/WorldTerrain.h"
#include "../Shared/Terrain.h"
#include "../Shared/Noise.h"
#include "ShaderTypes.h"

using namespace metal;

static constexpr constant uint32_t MaxTotalThreadsPerObjectThreadgroup = 1024;  // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxThreadgroupsPerMeshGrid = 512;            // Works with 65k, maybe more?
static constexpr constant uint32_t MaxTotalThreadsPerMeshThreadgroup = 1024;    // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxMeshletVertexCount = 256;
static constexpr constant uint32_t MaxMeshletPrimitivesCount = 512;

static constexpr constant uint32_t Density = 3;  // 1...3
static constexpr constant uint32_t VertexOctaves = 8;
static constexpr constant uint32_t FragmentOctaves = 24;

#define MORPH 1
#define TRIM_EDGES 1

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 p, float amplitude, float octaves, float epsilon) {
//  return fbm3(float3(cubeOrigin.xyz) * float3(p.x, 0, p.y), 0.000001, amplitude, 2, 0.5, 5, 1.0, 0.5, 0.5);
//  return fbm3(float3(p.x, 0, p.y), 0.1, amplitude, 2, 0.5, 5, 1.0, 0.5, 0.5);
  float3 cubeOffset = float3(p.x, 0, p.y);

//  float ff = 10;
//  float qd = 4;
//  int qo = 2;
//  float qf = 0.001;
//  float sd = 7;
//  int so = 3;
//  float sf = 0.0000008;
//  float3 o1 = ff*float3(-3.2, 9.2, -8.3)/(float)cubeSize;
//  float3 o2 = ff*float3(1.1, -3, 4.7)/(float)cubeSize;
//  float4 qx = fbmInf3(cubeOrigin, cubeSize, cubeOffset+qd*o1, qf, 1, qo, 0);
//  float4 qy = fbmInf3(cubeOrigin, cubeSize, cubeOffset+qd*o2, qf, 1, qo, 0);
//  float3 q = float3(qx.x, 0, qy.x) / (float)cubeSize;
//  float4 s = fbmInf3(cubeOrigin, cubeSize, cubeOffset + sd*q, sf, 10, so, 0);
  float4 s = fbmInf3(cubeOrigin, cubeSize, cubeOffset, 0.0000002, 3, 3, 0.3, 0);
  float ap = amplitude * s.x * s.x;

  float frequency = 0.00004;
  float sharpness = clamp(s.x, -1.0, 1.0);
  return fbmInf3(cubeOrigin, cubeSize, cubeOffset, frequency, ap, octaves, sharpness, 0);
}

typedef struct {
  int start, stop;
} StripRange;

StripRange stripRange(int row, bool isHalf) {
  // TODO: convert to array lookup.
  if (isHalf) {
    switch (row) {
      case 0:
        return { 0, 9 };      // 9
      case 1:
        return { 9, 18 };     // 9
      case 2:
        return { 18, 27 };    // 9
      case 3:
      default:
        return { 27, 36 };    // 9
    }
  } else {
    switch (row) {
      case 0:
        return { 0, 10 };     // 10
      case 1:
        return { 10, 18 };    // 8
      case 2:
        return { 18, 28 };    // 10
      case 3:
      default:
        return { 28, 36 };    // 8
    }
  }
}

typedef struct {
  int ringLevel;          // Level of the ring used for diagnostic colouring.
  bool xHalfStep;         // Whether this ring is a whole step or half step on x axis.
  bool yHalfStep;         // Whether this ring is a whole step or half step on y axis.
  int2 cubeCorner;        // Used for the cube origin for this ring.
  int cubeLength;         // The length of an edge of the ring used for cube terrain.
  int cubeRadius;         // Half the length of an edge of the ring.
  int cellSize;           // Length of an individual cell.
  float3 cellCornerLod;   // The corner of this ring used for mesh rendering.
  float cellSizeLod;      // Length of an individual cell in the mesh.
} Ring;

/*
 A ring is made up of 36 cell strips horizontally and vertically, with the center cut out.
 There are thus 72 half cell strips.
 Each cell is made up of 8 triangles in a star shape. Each triangle belongs to a half cell strip.
 
     -----
     |\|/|
     --X--
     |/|\|
     -----

 */
Ring makeRing(float3 ringCenterEyeOffsetLod, float lod, int2 eyeCell, int ringLevel) {
  int halfCellUnit = round(powr(2.0, ringLevel - 1));
  int cellUnit = 2 * halfCellUnit;
  int doubleCellUnit = 2 * cellUnit;
  int halfRingSize = 18 * cellUnit;
  int ringSize = 36 * cellUnit;

  int2 snappedDoubleEyeCell = doubleCellUnit * int2(floor(float2(eyeCell) / float2(doubleCellUnit)));
  int2 snappedEyeCell = cellUnit * int2(floor(float2(eyeCell) / float2(cellUnit)));
  int2 cubeCorner = snappedDoubleEyeCell - halfRingSize;
  int cubeLength = ringSize;
  int cubeRadius = halfRingSize;
  
  bool xHalfStep = snappedDoubleEyeCell.x == snappedEyeCell.x;
  bool yHalfStep = snappedDoubleEyeCell.y == snappedEyeCell.y;

  float cellUnitLod = (float)cellUnit / lod;
  float halfRingSizeLod = (float)halfRingSize / lod;
  float2 continuousRingCornerLod = ringCenterEyeOffsetLod.xz - halfRingSizeLod;

  float3 offset = float3((eyeCell.x - snappedDoubleEyeCell.x), 0, (eyeCell.y - snappedDoubleEyeCell.y));
  float3 cellCornerLod = float3(continuousRingCornerLod.x, ringCenterEyeOffsetLod.y, continuousRingCornerLod.y) - offset;

  return {
    ringLevel,
    xHalfStep,
    yHalfStep,
    cubeCorner,
    cubeLength,
    cubeRadius,
    cellUnit,
    cellCornerLod,
    cellUnitLod
  };
}

typedef struct {
  Ring ring;
  StripRange xStrips;
  StripRange yStrips;
  float time;
  int radius;
  float radiusLod;
  float amplitudeLod;
  simd_float3 eyeLod;
  float4x4 mvp;
  bool diagnosticMode;
} Payload;

[[
  object,
  max_total_threads_per_threadgroup(MaxTotalThreadsPerObjectThreadgroup),
  max_total_threadgroups_per_mesh_grid(MaxThreadgroupsPerMeshGrid)
]]
void terrainObject(object_data Payload& payload [[payload]],
                   mesh_grid_properties meshGridProperties,
                   constant Uniforms &uniforms [[buffer(1)]],
                   uint threadIndex [[thread_index_in_threadgroup]],
                   uint3 gridPosition [[threadgroup_position_in_grid]],
                   uint3 gridSize [[threadgroups_per_grid]]) {
  int ringLevel = gridPosition.z + uniforms.baseRingLevel; // Lowest ring level is 1.
  Ring ring = makeRing(uniforms.ringCenterEyeOffsetLod, uniforms.lod, uniforms.ringCenterCell, ringLevel);
  StripRange xStrips = stripRange(gridPosition.x, ring.xHalfStep);
  StripRange yStrips = stripRange(gridPosition.y, ring.yHalfStep);

#if TRIM_EDGES

  int2 tlOff = (ring.cubeCorner + uniforms.radius) / ring.cellSize;
  if (tlOff.x < 0) {
    xStrips.start = max(-tlOff.x, xStrips.start);
  }
  if (tlOff.y < 0) {
    yStrips.start = max(-tlOff.y, yStrips.start);
  }

  // TODO: problem here is that the top-level ring is offset a half when camera is close to opposite edge, leaving a gap. Adding another ring doesn't help because it's too big.
  int2 brOff = (ring.cubeCorner + ring.cubeLength - uniforms.radius) / ring.cellSize;
  if (brOff.x > 0) {
    xStrips.stop = min(36 - brOff.x, xStrips.stop);
  }
  if (brOff.y > 0) {
    yStrips.stop = min(36 - brOff.y, yStrips.stop);
  }

#endif
  
  bool isDegenerate = xStrips.start > xStrips.stop || yStrips.start > yStrips.stop;

  payload.ring = ring;
  payload.xStrips = xStrips;
  payload.yStrips = yStrips;
  payload.time = uniforms.time;
  payload.radius = uniforms.radius;
  payload.radiusLod = uniforms.radiusLod;
  payload.amplitudeLod = uniforms.amplitudeLod;
  payload.eyeLod = uniforms.ringCenterEyeOffsetLod;
  payload.mvp = uniforms.mvp;
  payload.diagnosticMode = uniforms.diagnosticMode;
  
  bool isCenter = gridPosition.x > 0 && gridPosition.x < gridSize.x - 1 && gridPosition.y > 0 && gridPosition.y < gridSize.y - 1;
  bool shouldRender = !isDegenerate && (!isCenter || ringLevel == uniforms.baseRingLevel);
  if (threadIndex == 0 && shouldRender) {
    auto meshes = 2 * Density;
    meshGridProperties.set_threadgroups_per_grid(uint3(meshes, meshes, 1));  // How many meshes to spawn per object.
  }
}

struct VertexOut {
  float4 position [[position]];
  float distance;
  float3 eye2world;
  float amplitudeLod;
  float radius;
  int ringLevel;          // Level of the ring used for diagnostic colouring.
  int2 cubeCorner;        // Used for the cube origin for this ring.
  int cubeLength;         // The length of an edge of the ring used for cube terrain.
  float2 cubeOffset;
  bool diagnosticMode;
};

struct PrimitiveOut {
  float4 colour;  // This has to be the first property for the shader compiler to hook it up. Why?
};

using TriangleMesh = metal::mesh<VertexOut, PrimitiveOut, MaxMeshletVertexCount, MaxMeshletPrimitivesCount, metal::topology::triangle>;

#define GRID_INDEX(i,j,w) ((j)*(w)+(i))

StripRange densify(StripRange undense, uint rank, uint iDensity) {
  float fDensity = (float)iDensity;
  int cells = undense.stop - undense.start;
  int start = floor((float)rank * (float)cells / fDensity) + undense.start;
  int _stop = floor((float)(rank + 1) * (float)cells / fDensity) + undense.start;
  int stop = (rank == (iDensity - 1)) ? undense.stop : _stop;
  start *= iDensity;
  stop *= iDensity;
  return { start, stop };
}

[[mesh, max_total_threads_per_threadgroup(MaxTotalThreadsPerMeshThreadgroup)]]
void terrainMesh(TriangleMesh output,
                 const object_data Payload& payload [[payload]],
                 uint threadIndex [[thread_index_in_threadgroup]],
                 uint3 threadPosition [[thread_position_in_threadgroup]],
                 uint2 meshIndex [[threadgroup_position_in_grid]],
                 uint2 numThreads [[threads_per_threadgroup]],
                 uint2 numMeshes [[threadgroups_per_grid]]) {
  // Find start and stop grid positions based on density.
  uint iDensity = numMeshes.x;  // Number of meshes is assumed to be square (i.e., x == y).
  auto xStrips = densify(payload.xStrips, meshIndex.x, iDensity);
  auto yStrips = densify(payload.yStrips, meshIndex.y, iDensity);
  
  float totalRingCells = 36.0 * (float)iDensity;

  // Create mesh vertices.
  float cellSizeLod = payload.ring.cellSizeLod / (float)iDensity;
  int numVertices = 0;
  for (int j = yStrips.start; j < yStrips.stop + 1; j++) {
    for (int i = xStrips.start; i < xStrips.stop + 1; i++) {

      float3 worldPositionLod = float3(i, 0, j) * cellSizeLod + payload.ring.cellCornerLod;
      float3 worldPositionFooLod = float3(i, 0, j) * cellSizeLod;

#if MORPH
      // Adjust vertices to avoid cracks.
      const float SQUARE_SIZE = cellSizeLod;
      const float SQUARE_SIZE_4 = 4.0 * SQUARE_SIZE;

      float3 worldCenterPositionLod = 0;
      float2 offsetFromCenter = float2(abs(worldPositionLod.x - worldCenterPositionLod.x),
                                       abs(worldPositionLod.z - worldCenterPositionLod.z));
      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
      float lodAlpha = taxicab_norm / (cellSizeLod * totalRingCells / 2.0);
      const float BLACK_POINT = 0.55;
      const float WHITE_POINT = 0.85;
      lodAlpha = (lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT);
      lodAlpha = saturate(lodAlpha);

      float2 m = fract(worldPositionFooLod.xz / SQUARE_SIZE_4);
      float2 offset = m - 0.5;
      const float minRadius = 0.35;
      if (abs(offset.x) < minRadius) {
        worldPositionFooLod.x += offset.x * lodAlpha * SQUARE_SIZE_4;
        worldPositionLod.x += offset.x * lodAlpha * SQUARE_SIZE_4;
      }
      if (abs(offset.y) < minRadius) {
        worldPositionFooLod.z += offset.y * lodAlpha * SQUARE_SIZE_4;
        worldPositionLod.z += offset.y * lodAlpha * SQUARE_SIZE_4;
      }
#endif
      float xd = worldPositionFooLod.x / cellSizeLod / totalRingCells;
      float zd = worldPositionFooLod.z / cellSizeLod / totalRingCells;
      float2 cubeOffset(xd, zd);  // TODO: this doesn't take into account morphing!

      float world2Eye = length(worldPositionLod);

      int3 cubeOrigin = int3(payload.ring.cubeCorner.x, payload.radius, payload.ring.cubeCorner.y);
      int cubeSize = payload.ring.cubeLength;
      float amplitude = payload.amplitudeLod;
      float maxOctaves = VertexOctaves;
      float minOctaves = 1.0;
      float octaves = adaptiveOctaves(world2Eye, minOctaves, maxOctaves, 10.0, payload.radiusLod, 0.09);
      float epsilon = adaptiveOctaves(world2Eye, 0.1, 1000, 1.0, payload.radiusLod, 0.5);
      float4 terrain = calculateTerrain(cubeOrigin, cubeSize, cubeOffset, amplitude, octaves, epsilon);

      // TODO: reinstate.
      worldPositionLod.y += terrain.x;
      
      float4 position = payload.mvp * float4(worldPositionLod, 1);

      VertexOut out;
      out.position = position;
      out.distance = world2Eye;
      out.eye2world = worldPositionLod;
      out.amplitudeLod = payload.amplitudeLod;
      out.radius = payload.radius;
      out.ringLevel = payload.ring.ringLevel;
      out.cubeCorner = payload.ring.cubeCorner;
      out.cubeLength = payload.ring.cubeLength;
      out.cubeOffset = cubeOffset;
      out.diagnosticMode = payload.diagnosticMode;
      output.set_vertex(numVertices++, out);
    }
  }

  // Create mesh edges.
  int meshVertexWidth = xStrips.stop - xStrips.start + 1;
  int numEdges = 0;
  int numTriangles = 0;
  for (int t = yStrips.start; t < yStrips.stop; t++) {
    for (int s = xStrips.start; s < xStrips.stop; s++) {
      int j = t - yStrips.start;
      int i = s - xStrips.start;
      if ((s + t) % 2 == 0) {
        // Top left to bottom right triangles.
        output.set_index(numEdges++, GRID_INDEX(i, j, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i, j + 1, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i + 1, j + 1, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i, j, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i + 1, j + 1, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i + 1, j, meshVertexWidth));
      } else {
        // Bottom left to top right triangles.
        output.set_index(numEdges++, GRID_INDEX(i, j, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i, j + 1, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i + 1, j, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i + 1, j, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i, j + 1, meshVertexWidth));
        output.set_index(numEdges++, GRID_INDEX(i + 1, j + 1, meshVertexWidth));
      }
      
      float r = s % 2;
      float g = t % 2;
      for (int p = 0; p < 2; p++) {
        PrimitiveOut out;
        float c = p % 2 == 0 ? 1 : 0;
        out.colour = float4(r, g, c, 1);
        output.set_primitive(numTriangles++, out);
      }
    }
  }
  
  if (threadIndex == 0) {
    output.set_primitive_count(numTriangles);
  }
}

typedef struct {
  VertexOut v;
  PrimitiveOut p;
} FragmentIn;

fragment float4 terrainFragment(FragmentIn in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(1)]]) {
  auto distanceLod = in.v.distance;
  float maxOctaves = FragmentOctaves;
  float minOctaves = 1.0;
  float octaves = adaptiveOctaves(distanceLod, minOctaves, maxOctaves, 10.0 / uniforms.lod, uniforms.radiusLod, 0.1);
  float epsilon = adaptiveOctaves(distanceLod, 0.1, 1000, 1.0, uniforms.radiusLod, 0.5);

  int3 cubeOrigin = int3(in.v.cubeCorner.x, in.v.radius, in.v.cubeCorner.y);
  int cubeSize = in.v.cubeLength;
  float2 cubeOffset = in.v.cubeOffset;
  float amplitude = in.v.amplitudeLod;

  // TODO: reinstate.
  float4 terrain = calculateTerrain(cubeOrigin, cubeSize, cubeOffset, amplitude, octaves, epsilon);

  float3 deriv = terrain.yzw;
  float3 gradient = -deriv;
  float3 normal = normalize(gradient);

  // TODO: sphericalize.
//  float ampl = uniforms.amplitudeLod;
//  float3 g = gradient / (uniforms.radiusLod + (ampl * noise.x));
//  float3 n = sphericalise_flat_gradient(g, ampl, normalize(in.unitPositionLod));

//  float3 worldPositionLod;
  float3 eye2World = normalize(in.v.eye2world);// worldPositionLod - uniforms.eyeLod);
  float3 world2Sun = float3(1, 0, 0);// normalize(uniforms.sunLod - in.v.worldPositionLod.xyz);
  float3 sun2World = -world2Sun;

  float3 rock(0.55, 0.34, 0.17);
  // TODO: water.
//  float3 water(0.1, 0.2, 0.7);
//  float3 material = in.v.worldPositionLod.y < uniforms.radiusLod ? water : rock;
  float3 material = rock;
  float sunStrength = saturate(dot(normal, world2Sun));
  float3 sunColour = float3(1.64, 1.27, 0.99);
  float3 colour = material * sunStrength * sunColour;

  // TODO: specular highlights.
//  float specular = pow(saturate(0.1 * dot(eye2World, reflect(world2Sun, normal))), 10.0);
//  colour += sunColour * specular;

  if (terrain.x <= 0) {
    colour = float3(0,0,1);
  }

  if (in.v.diagnosticMode) {
    auto patchColour = in.p.colour.xyz;
    auto ringColour = float3((float)(in.v.ringLevel % 3) / 3.0, (float)(in.v.ringLevel % 4) / 4.0, (float)(in.v.ringLevel % 2) / 2.0);
    colour = mix(colour, ringColour, 0.5);
    colour = mix(colour, patchColour, 0.2);
  } else {
    colour = applyFog(colour, distanceLod * uniforms.lod, eye2World, sun2World);
    colour = gammaCorrect(colour);
  }
  
  return float4(colour, 1.0);
}
