#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/WorldTerrain.h"
#include "../Shared/Terrain.h"
#include "../Shared/Noise.h"
#include "ShaderTypes.h"
#include "CubeSphereTerrain.h"

using namespace metal;

static constexpr constant uint32_t MaxTotalThreadsPerObjectThreadgroup = 1024;  // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxThreadgroupsPerMeshGrid = 512;            // Works with 65k, maybe more?
static constexpr constant uint32_t MaxTotalThreadsPerMeshThreadgroup = 1024;    // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxMeshletVertexCount = 256;
static constexpr constant uint32_t MaxMeshletPrimitivesCount = 512;

static constexpr constant uint32_t Density = 2;  // 1...3

#define MORPH 1
#define TRIM_EDGES 1

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
  float3 cellCorner;      // The corner of this ring used for mesh rendering.
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
Ring makeRing(float3 ringCenterEyeOffset, int2 eyeCell, int ringLevel) {
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

  float2 continuousRingCorner = ringCenterEyeOffset.xz - halfRingSize;

  float3 offset = float3((eyeCell.x - snappedDoubleEyeCell.x), 0, (eyeCell.y - snappedDoubleEyeCell.y));
  float3 cellCorner = float3(continuousRingCorner.x, ringCenterEyeOffset.y, continuousRingCorner.y) - offset;

  return {
    ringLevel,
    xHalfStep,
    yHalfStep,
    cubeCorner,
    cubeLength,
    cubeRadius,
    cellUnit,
    cellCorner
  };
}

typedef struct {
  Ring ring;
  StripRange xStrips;
  StripRange yStrips;
  float time;
  int radius;
  float amplitude;
  simd_float3 eye;
  float4x4 mvp;
  int diagnosticMode;
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
  Ring ring = makeRing(uniforms.ringCenterEyeOffset, uniforms.ringCenterCell, ringLevel);
  StripRange xStrips = stripRange(gridPosition.x, ring.xHalfStep);
  StripRange yStrips = stripRange(gridPosition.y, ring.yHalfStep);

#if TRIM_EDGES

  // Problem here is that the top-level ring is offset a half when camera is close to opposite edge, leaving a gap.
  // Adding another ring doesn't help because it's too big. So add an extra row to fully pad out the world at the top level.
  if (ringLevel == uniforms.maxRingLevel) {
    if (xStrips.stop == 36) {
      xStrips.stop = 37;
    }
    if (yStrips.stop == 36) {
      yStrips.stop = 37;
    }
  }

  // Trim top left edges.
  int2 tlOff = (ring.cubeCorner + uniforms.radius) / ring.cellSize;
  if (tlOff.x < 0) {
    xStrips.start = max(-tlOff.x, xStrips.start);
  }
  if (tlOff.y < 0) {
    yStrips.start = max(-tlOff.y, yStrips.start);
  }

  // Trim bottom right edges.
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
  payload.amplitude = uniforms.amplitude;
  payload.eye = uniforms.ringCenterEyeOffset;
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
  float amplitude;
  float radius;
  int ringLevel;          // Level of the ring used for diagnostic colouring.
  int2 cubeCorner;        // Used for the cube origin for this ring.
  int cubeLength;         // The length of an edge of the ring used for cube terrain.
  float2 cubeOffset;
  int diagnosticMode;
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

  uint iDensity = numMeshes.x;  // Number of meshes is assumed to be square (i.e., x == y).

  float cellSizeLod = payload.ring.cellSize / (float)iDensity;

  // Find start and stop grid positions based on density.
  auto xStrips = densify(payload.xStrips, meshIndex.x, iDensity);
  auto yStrips = densify(payload.yStrips, meshIndex.y, iDensity);
  
  float totalRingCells = 36.0 * (float)iDensity;

  // Create mesh vertices.
  int numVertices = 0;
  for (int j = yStrips.start; j < yStrips.stop + 1; j++) {
    for (int i = xStrips.start; i < xStrips.stop + 1; i++) {

      float3 worldPositionLod = float3(i, 0, j) * cellSizeLod + payload.ring.cellCorner;
      float3 worldPositionFooLod = float3(i, 0, j) * cellSizeLod;

#if MORPH

      // Adjust vertices to avoid cracks.
      const float SQUARE_SIZE = cellSizeLod;
      const float SQUARE_SIZE_4 = 4.0 * SQUARE_SIZE;

      float3 worldCenterPositionLod = -2*cellSizeLod;
      float2 offsetFromCenter = float2(abs(worldPositionLod.x - worldCenterPositionLod.x),
                                       abs(worldPositionLod.z - worldCenterPositionLod.z));
      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
      float lodAlpha = taxicab_norm / (cellSizeLod * totalRingCells / 2.0);
      const float BLACK_POINT = 0.55;
      const float WHITE_POINT = 0.95;
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
      float2 cubeOffset(xd, zd);

      float world2Eye = length(worldPositionLod);

      int3 cubeOrigin = int3(payload.ring.cubeCorner.x, payload.radius, payload.ring.cubeCorner.y);
      int cubeSize = payload.ring.cubeLength;
      float4 terrain = calculateTerrain(cubeOrigin, cubeSize, cubeOffset);

//      if (payload.diagnosticMode == 1) {
//        if (terrain.x < waterLevel) {
//          terrain = float4(waterLevel, 0, 1, 0);
//        }
//      }

      worldPositionLod.y += terrain.x;

      float4 position = payload.mvp * float4(worldPositionLod, 1);

      VertexOut out;
      out.position = position;
      out.distance = world2Eye;
      out.eye2world = worldPositionLod;
      out.amplitude = payload.amplitude;
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
  int3 cubeOrigin = int3(in.v.cubeCorner.x, in.v.radius, in.v.cubeCorner.y);
  int cubeSize = in.v.cubeLength;
  float2 cubeOffset = in.v.cubeOffset;

  GridPosition gp = makeGridPosition(cubeOrigin, cubeSize, float3(cubeOffset.x, 0, cubeOffset.y));
  float4 terrain = calculateTerrain(cubeOrigin, cubeSize, cubeOffset);

  float3 deriv = terrain.yzw;
  float3 gradient = float3(-deriv.x, 1, -deriv.z);
  float3 normal = normalize(gradient);

  float3 eye2World = normalize(in.v.eye2world);

  float3 sunDirection = float3(-1, 0.8, -1);// float3(cos(uniforms.time), 1, sin(uniforms.time)) * 1000;
  float3 world2Sun = normalize(sunDirection);
  float3 sun2World = -world2Sun;
  float sunStrength = saturate(dot(normal, world2Sun));
  float3 sunColour = float3(1.64, 1.27, 0.99);

  float3 dust(0.663, 0.475, 0.353);
  float3 rock(0.61, 0.4, 0.35);
  float3 rockA = rgb(185, 119, 62);
  float3 rockB = rgb(143, 75, 47);
  float3 rockC = rgb(121, 91, 69);
  float3 rockD = rgb(204, 190, 101);
  float3 strata[] = {float3(0.75, 0.33, 0.41), float3(0.63, 0.35, 0.4)};
  float3 deepWater = rgb(8, 31, 63);
  float3 shallowWater = rgb(36, 128, 149);
  float3 snow(1);

  float3 material = dust;

  float upness = dot(normal, float3(0, 1, 0));

  float4 snowline = 0;//fbmInf3(cubeOrigin, cubeSize, cubeOffset3, 0.005, 300, 4, 0, 0);

  float3 colour = material;

  float snowiness = smoothstep(0.85, 0.95, upness);
  float flatness = smoothstep(0.5, 0.55, upness);

  int band = int(ceil(abs(terrain.x) * 0.004 + snowline.x * 0.0005)) % 2;
  float3 strataColour = strata[band];
  float3 flatMaterial = rock;
  float3 steepMaterial = strataColour;
  material = mix(steepMaterial, flatMaterial, flatness);

//  if (terrain.x <= waterLevel) {
//    float mixing = smoothstep(waterLevel - 1000, waterLevel, terrain.x);
//    colour = mix(deepWater, shallowWater, mixing);
//  } else {
//    colour = material * sunStrength * sunColour;
//  }

  float normalisedHeight = (terrain.x / 1000);

  // TODO: specular highlights.
  float specular = pow(saturate(0.1 * dot(eye2World, reflect(world2Sun, normal))), 10.0);
  colour += sunColour * specular;

  switch (in.v.diagnosticMode) {
    case 0: {
      colour = material * sunStrength * sunColour;
      break;
    }
    case 1: {
      float patina = fbmSquared(gp, 0.000008, 12).x * normalisedHeight * normalisedHeight;
      float3 materialRamp[] = {
        rockA,
        rockD,
        rockB,
        rockC,
        rockB,
      };
      int c = floor(saturate(patina / 2.0 + 0.5) * (sizeof(materialRamp) / sizeof(float3)));
      float3 m = materialRamp[c];
      colour = m * sunStrength * sunColour;
//      if (normalisedHeight < 0) {
//        colour = mix(deepWater, shallowWater, saturate(normalisedHeight + 1));
//      } else {
//        material = mix(rockA, rockB, normalisedHeight);
//        colour = material * sunStrength * sunColour;
//      }
      break;
    }
    case 2: {
      colour = normal / 2.0 + 0.5;
      break;
    }
    case 3: {
      if (normalisedHeight < -1) {
        colour = float3(1, 0, 0); // red - below 0
      } else if (normalisedHeight > 1) {
        colour = float3(1, 1, 0); // yellow - above 1
      } else {
        colour = normalisedHeight / 2.0 + 0.5;
      }
      break;
    }
    case 4: {
      auto patchColour = in.p.colour.xyz;
      auto ringColour = float3((float)(in.v.ringLevel % 3) / 3.0, (float)(in.v.ringLevel % 4) / 4.0, (float)(in.v.ringLevel % 2) / 2.0);
      colour = mix(colour, ringColour, 0.5);
      colour = mix(colour, patchColour, 0.2);
      break;
    }
    case 5: {
      float distance = length(in.v.eye2world);
      colour = applyFog(colour, distance, eye2World, sun2World);
      colour = gammaCorrect(colour);
      break;
    }
  }

  return float4(colour, 1.0);
}
