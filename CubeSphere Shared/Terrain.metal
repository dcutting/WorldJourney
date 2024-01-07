#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/Noise.h"
#include "ShaderTypes.h"
using namespace metal;

static constexpr constant uint32_t MaxTotalThreadsPerObjectThreadgroup = 1024;  // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxThreadgroupsPerMeshGrid = 512;            // Works with 65k, maybe more?
static constexpr constant uint32_t MaxTotalThreadsPerMeshThreadgroup = 1024;    // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxMeshletVertexCount = 256;
static constexpr constant uint32_t MaxMeshletPrimitivesCount = 512;

typedef struct {
  float2 ringCorner;
  float ringSize;
  int mStart;
  int mStop;
  int nStart;
  int nStop;
  float time;
  float3 eye;
  float aspectRatio;
} Payload;

typedef struct {
  int start, stop;
} StripRange;

StripRange stripRange(int row, bool isHalf) {
  if (isHalf) {
    switch (row) {
      case 0:
        return { 0, 8 };
      case 1:
        return { 9, 17 };
      case 2:
        return { 18, 26 };
      case 3:
      default:
        return { 27, 35 };
    }
  } else {
    switch (row) {
      case 0:
        return { 0, 9 };
      case 1:
        return { 10, 17 };
      case 2:
        return { 18, 27 };
      case 3:
      default:
        return { 28, 35 };
    }
  }
}

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
  float ringSize = pow(2.0, (float)gridPosition.z);
  float halfGridUnit = ringSize / 36.0;
  float gridUnit = halfGridUnit * 2.0;
  float2 continuousRingCorner = uniforms.eye.xz - ringSize / 2.0;
  float2 discretizedRingCorner = gridUnit * (floor(continuousRingCorner / gridUnit));

  int xHalf = 1;
  int yHalf = 1;
  if (continuousRingCorner.x > discretizedRingCorner.x + halfGridUnit) {
    xHalf = 0;
  }
  if (continuousRingCorner.y > discretizedRingCorner.y + halfGridUnit) {
    yHalf = 0;
  }
  
  StripRange m = stripRange(gridPosition.x, xHalf);
  StripRange n = stripRange(gridPosition.y, yHalf);
  
  payload.ringCorner = discretizedRingCorner;
  payload.ringSize = ringSize;
  payload.mStart = m.start;
  payload.mStop = m.stop;
  payload.nStart = n.start;
  payload.nStop = n.stop;
  payload.time = uniforms.time;
  payload.eye = uniforms.eye;
  payload.aspectRatio = uniforms.screenWidth / uniforms.screenHeight;
  
  bool isCenter = gridPosition.x > 0 && gridPosition.x < gridSize.x - 1 && gridPosition.y > 0 && gridPosition.y < gridSize.y - 1;
  bool shouldRender = !isCenter || gridPosition.z == 0;
  if (threadIndex == 0 && shouldRender) {
    meshGridProperties.set_threadgroups_per_grid(uint3(1, 1, 1));  // How many meshes to spawn per object.
  }
}

struct VertexOut {
  float4 position [[position]];
};

struct PrimitiveOut {
  float4 colour;
};

using TriangleMesh = metal::mesh<VertexOut, PrimitiveOut, MaxMeshletVertexCount, MaxMeshletPrimitivesCount, metal::topology::triangle>;

#define GRID_INDEX(i,j,w) ((j)*(w)+(i))

float terrain(float x, float z, int size) {
//  return fbmInf3(319, size, float3(x, 1, z), 0.01, 4, 12, 1).x;
  return fbmd_7(float3(x, 1, z), 0.1, 12, 2, 0.5, 12).x;
//  return 2 * (sin(x * 0.5) + cos(z * 0.2));
}

[[mesh, max_total_threads_per_threadgroup(MaxTotalThreadsPerMeshThreadgroup)]]
void terrainMesh(TriangleMesh output,
                 const object_data Payload& payload [[payload]],
                 uint threadIndex [[thread_index_in_threadgroup]],
                 uint3 threadPosition [[thread_position_in_threadgroup]],
                 uint2 meshIndex [[threadgroup_position_in_grid]],
                 uint2 numThreads [[threads_per_threadgroup]],
                 uint2 numMeshes [[threadgroups_per_grid]]) {
  float4x4 translate = matrix_translate(-payload.eye);
  float4x4 rotate = matrix_rotate(M_PI_F / 2.0, float3(1, 0, 0));
  float4x4 perspective = matrix_perspective(0.85, payload.aspectRatio, 0.001, 30000);

  // Create mesh vertices.
  float cellSize = payload.ringSize / 36.0;
  int numVertices = 0;
  for (int j = payload.nStart; j <= payload.nStop + 1; j++) {
    for (int i = payload.mStart; i <= payload.mStop + 1; i++) {
      float x = i * cellSize + payload.ringCorner.x;
      float z = j * cellSize + payload.ringCorner.y;
      float y = terrain(x, z, cellSize);
      float4 p(x, y, z, 1);
      float4 vp = perspective * rotate * translate * p;
      VertexOut out;
      out.position = vp;
      output.set_vertex(numVertices++, out);
    }
  }

  // Create mesh edges.
  int meshVertexWidth = payload.mStop - payload.mStart + 2;
  int numEdges = 0;
  int numTriangles = 0;
  for (int t = payload.nStart; t <= payload.nStop; t++) {
    for (int s = payload.mStart; s <= payload.mStop; s++) {
      int j = t - payload.nStart;
      int i = s - payload.mStart;
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
        float c = (float)p / 2.0 * 0.8 + 0.2;
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
  PrimitiveOut p;
} FragmentIn;

fragment float4 terrainFragment(FragmentIn in [[stage_in]]) {
  return in.p.colour;
}
