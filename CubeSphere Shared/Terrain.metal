#include <metal_stdlib>
#include "../Shared/InfiniteNoise.h"
#include "ShaderTypes.h"

using namespace metal;

static constexpr constant uint32_t MaxTotalThreadsPerObjectThreadgroup = 1024;  // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxThreadgroupsPerMeshGrid = 512;            // Works with 65k, maybe more?
static constexpr constant uint32_t MaxTotalThreadsPerMeshThreadgroup = 1024;    // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxMeshletVertexCount = 256;
static constexpr constant uint32_t MaxMeshletPrimitivesCount = 512;

static constexpr constant uint32_t Density = 2;  // 1...3
static constexpr constant uint32_t VertexOctaves = 10;
//static constexpr constant uint32_t FragmentOctaves = 14;
//static constexpr constant float FragmentOctaveRangeM = 4096;

#define MORPH 1
#define FRAGMENT_NORMALS 0

float4 calculateTerrain(int3 cubeOrigin, int cubeSize, float2 p, float amplitude, float octaves) {
  float3 cubeOffset = float3(p.x, 0, p.y);
  float frequency = 0.00003;
  float sharpness = 0.0;
  return fbmInf3(cubeOrigin, cubeSize, cubeOffset, frequency, amplitude, octaves, sharpness);
}

typedef struct {
  int start, stop;
} StripRange;

StripRange stripRange(int row, bool isHalf) {
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
  int2 corner;
  int size;
  float2 cornerLod;
  float cellSizeLod;
  float halfCellSizeLod;
  float sizeLod;
  int level;
} Ring;

Ring makeRing(float2 positionLod, float lod, int3 eyeCell, int ringLevel) {
  int iHalfRingSize = round(powr(2.0, ringLevel - 1));
  int iRingSize = iHalfRingSize * 2;
  float halfRingSizeLod = (float)iHalfRingSize / lod;
  float ringSizeLod = halfRingSizeLod * 2.0;
  float gridCellSizeLod = halfRingSizeLod / 18.0;
  float halfCellSizeLod = halfRingSizeLod / 36.0;
  float doubleGridCellSizeLod = halfRingSizeLod / 9.0;
  float2 continuousRingCornerLod = positionLod - halfRingSizeLod;
  float2 discretizedRingCornerLod = doubleGridCellSizeLod * (floor(continuousRingCornerLod / doubleGridCellSizeLod));
  return {
    eyeCell.xz - iHalfRingSize,
    iRingSize,
    discretizedRingCornerLod,
    gridCellSizeLod,
    halfCellSizeLod,
    ringSizeLod,
    ringLevel
  };
}

typedef struct {
  Ring ring;
  StripRange xStrips;
  StripRange yStrips;
  float time;
  int radius;
  float radiusLod;
  float3 eyeLod;
  float3 sunLod;
  float amplitudeLod;
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
  auto eyeLod = uniforms.eyeLod;
  int ringLevel = gridPosition.z + uniforms.baseRingLevel; // Lowest ring level is 1.
  Ring ring = makeRing(eyeLod.xz, uniforms.lod, uniforms.eyeCell, ringLevel);
  Ring innerRing = makeRing(eyeLod.xz, uniforms.lod, uniforms.eyeCell, ringLevel - 1);
  float2 grid = abs((ring.cornerLod + 9.0 * ring.cellSizeLod) - innerRing.cornerLod);
  int xHalf = grid.x < ring.halfCellSizeLod ? 1 : 0;
  int yHalf = grid.y < ring.halfCellSizeLod ? 1 : 0;
  
  StripRange xStrips = stripRange(gridPosition.x, xHalf);
  StripRange yStrips = stripRange(gridPosition.y, yHalf);
  
  payload.ring = ring;
  payload.xStrips = xStrips;
  payload.yStrips = yStrips;
  payload.time = uniforms.time;
  payload.radius = uniforms.radius;
  payload.radiusLod = uniforms.radiusLod;
  payload.eyeLod = uniforms.eyeLod;
  payload.sunLod = uniforms.sunLod;
  payload.amplitudeLod = uniforms.amplitudeLod;
  payload.mvp = uniforms.mvp;
  payload.diagnosticMode = uniforms.diagnosticMode;
  
  bool isCenter = gridPosition.x > 0 && gridPosition.x < gridSize.x - 1 && gridPosition.y > 0 && gridPosition.y < gridSize.y - 1;
  bool shouldRender = !isCenter || ringLevel == uniforms.baseRingLevel;
  if (threadIndex == 0 && shouldRender) {
    auto meshes = 2 * Density;
    meshGridProperties.set_threadgroups_per_grid(uint3(meshes, meshes, 1));  // How many meshes to spawn per object.
  }
}

struct VertexOut {
  float4 position [[position]];
  float4 worldPositionLod;
  float3 worldNormal;
  simd_float3 eyeLod;
  simd_float3 sunLod;
};

struct PrimitiveOut {
  float4 colour;  // This has to be the first property for the shader compiler to hook it up. Why?
  int ringLevel;
  bool diagnosticMode;
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
      float xd = i / totalRingCells;
      float zd = j / totalRingCells;
      float2 cubeOffset(xd, zd);  // This is wrong, because it doesn't take into account morphing!

      float x = i * cellSizeLod + payload.ring.cornerLod.x;
      float z = j * cellSizeLod + payload.ring.cornerLod.y;

      float4 worldPositionLod = float4(x, 0, z, 1);

#if MORPH
      // Adjust vertices to avoid cracks.
      const float SQUARE_SIZE = cellSizeLod;
      const float SQUARE_SIZE_4 = 4.0 * SQUARE_SIZE;

      float3 worldCenterPositionLod = payload.eyeLod;
      float2 offsetFromCenter = float2(abs(worldPositionLod.x - worldCenterPositionLod.x),
                                       abs(worldPositionLod.z - worldCenterPositionLod.z));
      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
      float lodAlpha = taxicab_norm / (payload.ring.sizeLod / 2.0);
      const float BLACK_POINT = 0.56;
      const float WHITE_POINT = 0.94;
      lodAlpha = (lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT);
      lodAlpha = saturate(lodAlpha);
            
      float2 m = fract(worldPositionLod.xz / SQUARE_SIZE_4);
      float2 offset = m - 0.5;
      const float minRadius = 0.26;
      if (abs(offset.x) < minRadius) {
        worldPositionLod.x += offset.x * lodAlpha * SQUARE_SIZE_4;
      }
      if (abs(offset.y) < minRadius) {
        worldPositionLod.z += offset.y * lodAlpha * SQUARE_SIZE_4;
      }
#endif

      int3 cubeOrigin = int3(payload.ring.corner.x, payload.radius, payload.ring.corner.y);
      int cubeSize = payload.ring.size;
      float amplitude = payload.amplitudeLod;
      float octaves = VertexOctaves;
      float4 terrain = calculateTerrain(cubeOrigin, cubeSize, cubeOffset, amplitude, octaves);
      
      worldPositionLod.y = terrain.x + payload.radiusLod;
      float4 position = payload.mvp * worldPositionLod;
      VertexOut out;
      out.position = position;
      out.worldPositionLod = worldPositionLod;
      out.worldNormal = terrain.yzw;
      out.eyeLod = payload.eyeLod;
      out.sunLod = payload.sunLod;
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
        out.ringLevel = payload.ring.level;
        out.diagnosticMode = payload.diagnosticMode;
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
//  auto distanceLod = distance(in.v.eyeLod, in.v.worldPositionLod.xyz);

#if FRAGMENT_NORMALS
  // TODO: adaptive octaves.
//  float maxOctaves = FragmentOctaves;
//  float minOctaves = 1.0;
//  float octaveRangeLod = FragmentOctaveRangeM / uniforms.lod;
//  auto partialOctaves = saturate((octaveRangeLod-distanceLod)/octaveRangeLod);
//  auto octaves = min(maxOctaves, max(minOctaves, maxOctaves*partialOctaves + minOctaves));
  
//  int3 cubeOrigin(4);
//  int cubeSize = 300;
//  float2 cubeOffset = in.v.worldPositionLod.xz;
//  float amplitude = 40;
//  auto octaves = VertexOctaves;
//  float4 terrain = calculateTerrain(cubeOrigin, cubeSize, cubeOffset, amplitude, octaves);
  
  float3 deriv = terrain.yzw;
#else
  float3 deriv = in.v.worldNormal;
#endif
  float3 gradient = -deriv;
  float3 normal = normalize(gradient);

  // TODO: sphericalize.
//  float ampl = uniforms.amplitudeLod;
//  float3 g = gradient / (uniforms.radiusLod + (ampl * noise.x));
//  float3 n = sphericalise_flat_gradient(g, ampl, normalize(in.unitPositionLod));

//  float3 eye2World = normalize(in.v.worldPositionLod.xyz - in.v.eyeLod);
//  float3 sun2World = normalize(in.v.worldPositionLod.xyz - in.v.sunLod);
  float3 world2Sun = normalize(in.v.sunLod - in.v.worldPositionLod.xyz);
  
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
  
  if (in.p.diagnosticMode) {
    auto patchColour = in.p.colour.xyz;
    auto ringColour = float3((float)(in.p.ringLevel % 3) / 3.0, (float)(in.p.ringLevel % 4) / 4.0, (float)(in.p.ringLevel % 2) / 2.0);
    colour = mix(colour, ringColour, 0.5);
    colour = mix(colour, patchColour, 0.2);
    // TODO: fog and gamma.
//  } else {
//    colour = applyFog(colour, distanceLod * uniforms.lod, eye2World, sun2World);
//    colour = gammaCorrect(colour);
  }
  
  return float4(colour, 1.0);
}
