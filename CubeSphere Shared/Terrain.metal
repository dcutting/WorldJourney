#include <metal_stdlib>
#include "../Shared/Maths.h"
#include "../Shared/InfiniteNoise.h"
#include "../Shared/Noise.h"
#include "../Shared/Terrain.h"
#include "ShaderTypes.h"
using namespace metal;

static constexpr constant uint32_t MaxTotalThreadsPerObjectThreadgroup = 1024;  // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxThreadgroupsPerMeshGrid = 512;            // Works with 65k, maybe more?
static constexpr constant uint32_t MaxTotalThreadsPerMeshThreadgroup = 1024;    // 1024 seems to be max on iPhone 15 Pro Max.
static constexpr constant uint32_t MaxMeshletVertexCount = 256;
static constexpr constant uint32_t MaxMeshletPrimitivesCount = 512;

#define MORPH 0
#define FRAGMENT_NORMALS 0

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
        return { 0, 8 };      // 9
      case 1:
        return { 9, 17 };     // 9
      case 2:
        return { 18, 26 };    // 9
      case 3:
      default:
        return { 27, 35 };    // 9
    }
  } else {
    switch (row) {
      case 0:
        return { 0, 9 };      // 10
      case 1:
        return { 10, 17 };    // 8
      case 2:
        return { 18, 27 };    // 10
      case 3:
      default:
        return { 28, 35 };    // 8
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
  float4 worldPosition;
  float3 worldNormal;
};

struct PrimitiveOut {
  float4 colour;
};

using TriangleMesh = metal::mesh<VertexOut, PrimitiveOut, MaxMeshletVertexCount, MaxMeshletPrimitivesCount, metal::topology::triangle>;

#define GRID_INDEX(i,j,w) ((j)*(w)+(i))

float2 warp(float2 p, float f, float2 dx, float2 dy) {
  int o = 4;

  float3 qx = fbm2(p+dx, f, 1, 2, 0.5, o, 1, 0, 0);
  float3 qy = fbm2(p+dy, f, 1, 2, 0.5, o, 1, 0, 0);
  float2 q = float2(qx.x, qy.x);
  return q;
}

float4 terrain(float x, float z, int o) {
//  return fbmInf3(319, size, float3(x, 1, z), 0.01, 4, 12, 1).x;
//  return 2 * (sin(x * 0.5) + cos(z * 0.2));
//  float d = 8.0;
//  
  float2 p(x, z);
//
//  float2 q = warp(p, 0.0001, float2(0, 0), float2(5.2, 1.3));
//  float2 s = warp(p + d*q, 0.0001, float2(1.7, 9.2), float2(8.3, 2.8));
//  float3 terrain = fbm2(x, p, 0.1, pow(0.5*s.x+1, 2.0), 2, 0.5, so, o, octaveMix, 0.5, 0.05);// saturate(pow(mixer2.x, 4)));
//  float3 noise = fbm2(p, 0.01, 20*pow(2*q.x+1,2), 2, 0.5, o, 1, s.x, 0.8);
  float3 noise = fbm2(p, 0.0001, 20.0, 2, 0.5, o, 1, 0.5, 0.0);

////  auto s = fbmd_7(float3(x, 1, z), 0.0001, 1, 2.7, 0.3, 8).x;
//  float3 noise = fbm2(319, 320, float3(x, 1, z), 0.008, 30, 2, 0.5, o, 1, s, 0.5);
  return float4(noise.x, noise.y, -1, noise.z);
//  n = normalize(float3(-dv.x, 1, -dv.y));
}

constant static int OCTAVES = 10;

#define HLSLFMOD(x,y) ((x) - (y) * trunc((x)/(y)))

[[mesh, max_total_threads_per_threadgroup(MaxTotalThreadsPerMeshThreadgroup)]]
void terrainMesh(TriangleMesh output,
                 const object_data Payload& payload [[payload]],
                 uint threadIndex [[thread_index_in_threadgroup]],
                 uint3 threadPosition [[thread_position_in_threadgroup]],
                 uint2 meshIndex [[threadgroup_position_in_grid]],
                 uint2 numThreads [[threads_per_threadgroup]],
                 uint2 numMeshes [[threadgroups_per_grid]]) {
  float4x4 translate = matrix_translate(-payload.eye);
  float4x4 rotate = matrix_rotate(M_PI_F/2, float3(1, 0, 0));
//  float4x4 rotate = matrix_rotate(M_PI_F/2.0 /* + (0.5 + 0.5*sin(payload.time))*/, 1.0 /*float3((sin(payload.time)+2.0)/4+0.5*/, 0, 0));
//  float4x4 rotate = matrix_rotate(M_PI_F/8.0, float3(1.0, 0, 0));
  float4x4 perspective = matrix_perspective(0.85, payload.aspectRatio, 0.01, 10000);

  // Create mesh vertices.
  float cellSize = payload.ringSize / 36.0;
  int numVertices = 0;
  for (int j = payload.nStart; j <= payload.nStop + 1; j++) {
    for (int i = payload.mStart; i <= payload.mStop + 1; i++) {
      float x = i * cellSize + payload.ringCorner.x;
      float z = j * cellSize + payload.ringCorner.y;

      float3 worldPos = float3(x, 0, z);
#if MORPH
      // Adjust vertices to avoid cracks.
      const float SQUARE_SIZE = cellSize;
      const float SQUARE_SIZE_4 = 4.0 * SQUARE_SIZE;
      const float BASE_DENSITY = 10.0;
      float3 oceanCenterPosWorld = payload.eye;
//      worldPos.xz -= fmod(oceanCenterPosWorld.xz, 2.0 * SQUARE_SIZE); // this uses hlsl fmod, not glsl mod (sign is different).
      float2 offsetFromCenter = float2(abs(worldPos.x - oceanCenterPosWorld.x), abs(worldPos.z - oceanCenterPosWorld.z));
      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
      float idealSquareSize = taxicab_norm / BASE_DENSITY;
      float lodAlpha = idealSquareSize / SQUARE_SIZE - 1.0;
      const float BLACK_POINT = 0.15;
      const float WHITE_POINT = 0.85;
      lodAlpha = max((lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT), 0.0);
      const float meshScaleLerp = 0.0;  // what is this?
      lodAlpha = min(lodAlpha + meshScaleLerp, 1.0);
      float2 m = fract(worldPos.xz / SQUARE_SIZE_4);
      float2 offset = m - 0.5;
      const float minRadius = 0.26;
      if (abs(offset.x) < minRadius) {
        worldPos.x += offset.x * lodAlpha * SQUARE_SIZE_4;
      }
      if (abs(offset.y) < minRadius) {
        worldPos.z += offset.y * lodAlpha * SQUARE_SIZE_4;
      }
#endif

      float4 t = terrain(worldPos.x, worldPos.z, OCTAVES);
      float y = t.x;
      float4 p(worldPos.x, y, worldPos.z, 1);
      float4 vp = perspective * rotate * translate * p;
      VertexOut out;
      out.position = vp;
      out.worldPosition = p;
      out.worldNormal = t.yzw;
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
        float c = p % 2 == 0 ? 1 : 0;// (float)p / 2.0 * 0.8 + 0.2;
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
  auto p = in.v.worldPosition;
  auto d = distance(uniforms.eye, in.v.worldPosition.xyz);
  auto range = 6000.0;
  float maxO = 10;
  auto minO = 1.0;
  auto o = min(maxO, max(minO, maxO*(pow((range-d)/range, 0.5))+minO));
  auto t = terrain(p.x, p.z, o);
//  auto normal = t.yzw;
//  auto normalColour = float4((normalize(normal) + 1) / 2.0, 1);
//  auto colour = normalColour;
//  return colour;
#if FRAGMENT_NORMALS
  float3 deriv = t.yzw;
#else
  float3 deriv = in.v.worldNormal;
#endif
  float3 gradient = -deriv;
//#else
//  float3 deriv = in.noise.yzw;
//  float3 gradient = -deriv;
//#endif
//#endif
  
//  float3 gradient = float3(1, 0, 0);
  float3 n = normalize(gradient);
//  float3 n = normalize(gradient);
  
//  float ampl = uniforms.amplitudeLod;
//  float3 g = gradient / (uniforms.radiusLod + (ampl * noise.x));
//  float3 n = sphericalise_flat_gradient(g, ampl, normalize(in.unitPositionLod));

//  float3 eye2World = normalize(in.worldPositionLod - uniforms.eyeLod);
  float3 sun = float3(10000, 2000, 1000);
  float3 world2Sun = normalize(sun - in.v.worldPosition.xyz);
  float sunStrength = saturate(dot(n, world2Sun));

  // Make dark bits easier to see.
//  sunStrength = sunStrength * 0.9 + 0.1;
  
  float3 sunColour = float3(1.64,1.27,0.99);
  float3 lin = sunStrength;
  lin *= sunColour;
  
  float3 rock(0.21, 0.2, 0.2);
//  float3 water(0.1, 0.1, 0.7);
  float3 material = rock;//in.v.worldPosition.y < uniforms.radiusLod ? water : rock;
  material *= lin;

//  float shininess = 0.1;
  float3 colour = material * sunStrength * sunColour;

//  float3 rWorld2Sun = reflect(world2Sun, n);
//  float spec = dot(eye2World, rWorld2Sun);
//  float specStrength = saturate(shininess * spec);
//  specStrength = pow(specStrength, 10.0);
//  colour += sunColour * specStrength;
  
  colour = material * sunStrength;
  float3 eye2World = normalize(in.v.worldPosition.xyz - uniforms.eye);
  float3 sun2World = normalize(in.v.worldPosition.xyz - sun);
//  colour = applyFog(colour, d * 0.1, eye2World, sun2World);

//  colour = n / 2.0 + 0.5;
//  float tc = saturate(log((float)in.tier) / 10.0);
//  colour = float3(tc, tc, 1-tc);

#if FRAGMENT_NORMALS
  colour = pow(colour, float3(1.0/2.2));
#else
  auto patchColour = in.p.colour.xyz;
  colour = mix(colour, patchColour, 0.5);
#endif
  
  return float4(colour, 1.0);
}
