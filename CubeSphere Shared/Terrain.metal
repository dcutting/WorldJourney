#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/Terrain.h"
#include "../Shared/WorldTerrain.h"
#include "ShaderTypes.h"

using namespace metal;

static constexpr constant uint32_t MaxTotalThreadsPerObjectThreadgroup = 1024;  // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxThreadgroupsPerMeshGrid = 512;            // Works with 65k, maybe more?
static constexpr constant uint32_t MaxTotalThreadsPerMeshThreadgroup = 1024;    // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxMeshletVertexCount = 256;
static constexpr constant uint32_t MaxMeshletPrimitivesCount = 512;

static constexpr constant uint32_t Density = 2;  // 1...3
static constexpr constant uint32_t VertexOctaves = 10;
static constexpr constant uint32_t FragmentOctaves = 14;
static constexpr constant float FragmentOctaveRange = 4096;

#define MORPH 1
#define FRAGMENT_NORMALS 1

float4 calculateTerrain(float2 p, int octaves) {
  return sampleInf(int3(4), 300, float3(p.x, 1, p.y), 40, octaves, 0);
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
  float2 corner;
  float cellSize;
  float halfCellSize;
  float size;
  int level;
} Ring;

Ring corner(float2 p, int ringLevel) {
  int power = round(powr(2.0, ringLevel));
  float gridCellSize = power / 36.0;
  float halfCellSize = gridCellSize / 2.0;
  float doubleGridCellSize = 2.0 * gridCellSize;
  float ringSize = 36.0 * gridCellSize;
  float halfRingSize = 18.0 * gridCellSize;
  float2 continuousRingCorner = p - halfRingSize;
  float2 discretizedRingCorner = doubleGridCellSize * (floor(continuousRingCorner / doubleGridCellSize));
  return { discretizedRingCorner, gridCellSize, halfCellSize, ringSize, ringLevel };
}

typedef struct {
  Ring ring;
  StripRange m;
  StripRange n;
  float time;
  float3 eyeLod;
  float3 sunLod;
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
  int ringLevel = gridPosition.z;
  Ring ring = corner(eyeLod.xz, ringLevel);
  Ring innerRing = corner(eyeLod.xz, ringLevel - 1);
  float2 grid = abs((ring.corner + 9.0 * ring.cellSize) - innerRing.corner);
  int xHalf = grid.x < ring.halfCellSize ? 1 : 0;
  int yHalf = grid.y < ring.halfCellSize ? 1 : 0;
  
  StripRange m = stripRange(gridPosition.x, xHalf);
  StripRange n = stripRange(gridPosition.y, yHalf);
  
  payload.ring = ring;
  payload.m = m;
  payload.n = n;
  payload.time = uniforms.time;
  payload.eyeLod = uniforms.eyeLod;
  payload.sunLod = uniforms.sunLod;
  payload.mvp = uniforms.mvp;
  payload.diagnosticMode = uniforms.diagnosticMode;
  
  bool isCenter = gridPosition.x > 0 && gridPosition.x < gridSize.x - 1 && gridPosition.y > 0 && gridPosition.y < gridSize.y - 1;
  bool shouldRender = !isCenter || ringLevel == 0;
  if (threadIndex == 0 && shouldRender) {
    auto meshes = 2 * Density;
    meshGridProperties.set_threadgroups_per_grid(uint3(meshes, meshes, 1));  // How many meshes to spawn per object.
  }
}

struct VertexOut {
  float4 position [[position]];
  float4 worldPosition;
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
  auto m = densify(payload.m, meshIndex.x, iDensity);
  auto n = densify(payload.n, meshIndex.y, iDensity);

  // Create mesh vertices.
  float cellSize = payload.ring.size / 36.0 / (float)iDensity;
  int numVertices = 0;
  for (int j = n.start; j < n.stop + 1; j++) {
    for (int i = m.start; i < m.stop + 1; i++) {
      float x = i * cellSize + payload.ring.corner.x;
      float z = j * cellSize + payload.ring.corner.y;

      float4 worldPosition = float4(x, 0, z, 1);

#if MORPH
      // Adjust vertices to avoid cracks.
      const float SQUARE_SIZE = cellSize;
      const float SQUARE_SIZE_4 = 4.0 * SQUARE_SIZE;

      float3 worldCenterPosition = payload.eyeLod;
      float2 offsetFromCenter = float2(abs(worldPosition.x - worldCenterPosition.x), abs(worldPosition.z - worldCenterPosition.z));
      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
      float lodAlpha = taxicab_norm / (payload.ring.size / 2.0);
      const float BLACK_POINT = 0.56;
      const float WHITE_POINT = 0.94;
      lodAlpha = (lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT);
      lodAlpha = saturate(lodAlpha);
            
      float2 m = fract(worldPosition.xz / SQUARE_SIZE_4);
      float2 offset = m - 0.5;
      const float minRadius = 0.26;
      if (abs(offset.x) < minRadius) {
        worldPosition.x += offset.x * lodAlpha * SQUARE_SIZE_4;
      }
      if (abs(offset.y) < minRadius) {
        worldPosition.z += offset.y * lodAlpha * SQUARE_SIZE_4;
      }
#endif

      float4 terrain = calculateTerrain(worldPosition.xz, VertexOctaves);
      worldPosition.y = terrain.x;
      float4 position = payload.mvp * worldPosition;
      VertexOut out;
      out.position = position;
      out.worldPosition = worldPosition;
      out.worldNormal = terrain.yzw;
      out.eyeLod = payload.eyeLod;
      out.sunLod = payload.sunLod;
      output.set_vertex(numVertices++, out);
    }
  }

  // Create mesh edges.
  int meshVertexWidth = m.stop - m.start + 1;
  int numEdges = 0;
  int numTriangles = 0;
  for (int t = n.start; t < n.stop; t++) {
    for (int s = m.start; s < m.stop; s++) {
      int j = t - n.start;
      int i = s - m.start;
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
  auto d = distance(in.v.eyeLod, in.v.worldPosition.xyz);

#if FRAGMENT_NORMALS
  float maxOctaves = FragmentOctaves;
  auto minOctaves = 1.0;
  auto partialOctaves = saturate((FragmentOctaveRange-d)/FragmentOctaveRange);
  auto octaves = min(maxOctaves, max(minOctaves, maxOctaves*partialOctaves + minOctaves));
  auto terrain = calculateTerrain(in.v.worldPosition.xz, octaves);
  float3 deriv = terrain.yzw;
#else
  float3 deriv = in.v.worldNormal;
#endif
  float3 gradient = -deriv;
  float3 normal = normalize(gradient);
  
//  float ampl = uniforms.amplitudeLod;
//  float3 g = gradient / (uniforms.radiusLod + (ampl * noise.x));
//  float3 n = sphericalise_flat_gradient(g, ampl, normalize(in.unitPositionLod));

  float3 eye2World = normalize(in.v.worldPosition.xyz - in.v.eyeLod);
  float3 sun2World = normalize(in.v.worldPosition.xyz - in.v.sunLod);
  float3 world2Sun = normalize(in.v.sunLod - in.v.worldPosition.xyz);
  
  float3 rock(0.55, 0.34, 0.17);
  float3 water(0.1, 0.2, 0.7);
  float3 material = in.v.worldPosition.y < uniforms.radiusLod ? water : rock;
  float sunStrength = saturate(dot(normal, world2Sun));
  float3 sunColour = float3(1.64, 1.27, 0.99);
  float3 colour = material * sunStrength * sunColour;

  float specular = pow(saturate(0.1 * dot(eye2World, reflect(world2Sun, normal))), 10.0);
  colour += sunColour * specular;
  
  if (in.p.diagnosticMode) {
    auto patchColour = in.p.colour.xyz;
    auto ringColour = float3((float)(in.p.ringLevel % 3) / 3.0, (float)(in.p.ringLevel % 4) / 4.0, (float)(in.p.ringLevel % 2) / 2.0);
    colour = mix(colour, ringColour, 0.5);
    colour = mix(colour, patchColour, 0.2);
  } else {
    colour = applyFog(colour, d, eye2World, sun2World);
    colour = gammaCorrect(colour);
  }
  
  return float4(colour, 1.0);
}
