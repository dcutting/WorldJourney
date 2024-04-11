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
#define FRAGMENT_NORMALS 1

static constexpr constant uint32_t Density = 4;  // power of 2, max. 4.
static constexpr constant uint32_t EyeOctaves = 3;
static constexpr constant uint32_t VertexOctaves = 9;
static constexpr constant uint32_t FragmentOctaves = 12;
static constexpr constant float FragmentOctaveRange = 4096;

// Returns a value between -1 and 1.
float2 warp(float2 p, float f, float2 dx, float2 dy) {
  int o = 3;

  float3 qx = fbm2(p+dx, f, 1, 2, 0.5, o, 1, 0, 0);
  float3 qy = fbm2(p+dy, f, 1, 2, 0.5, o, 1, 0, 0);
  float2 q = float2(qx.x, qy.x);
  return q / 2.0;
}

float4 terrain(float2 p, int octaves) {
  float octaveMix = 1.0;
  
  float3 qx = fbm2(p+float2(-2.2, -2.3), 0.1, 1, 2, 0.5, 3, 1, 0, 0);
  float3 qy = fbm2(p+float2(4.2, 3.1), 0.1, 1, 2, 0.5, 3, 1, 0, 0);
  float2 q = float2(qx.x, qy.x);
  float3 d = fbm2(p, 0.05, 1, 2, 0.5, 4, 1, 0, 0);
  float qxx = saturate(qx.x*0.5+0.5);
  float3 noise = fbm2(p + 2*d.x*q, 0.1, pow(qxx*1.2, 2.0), 2, 0.498, octaves, octaveMix, powr(d.x/2.0, 3.0), 0.002);

//  float frequency = 0.0001;
//  float amplitude = 8000.0;
//  float lacunarity = 2.0;
//  float persistence = 0.5;
//
//  float3 amp = fbm2(p+float2(-3.1, 5.9), 0.00001, 1, 2, 0.5, 3, 1, 0, 0);
//  float3 qx = fbm2(p+float2(-2.2, -2.3), 0.0001, 1, 2, 0.5, 3, 1, 0, 0);
//  float3 qy = fbm2(p+float2(4.2, 3.1), 0.0001, 1, 2, 0.5, 3, 1, 0, 0);
//  float2 q = float2(qx.x, qy.x);
//  float3 d = fbm2(p, 0.1, 1, 2, 0.5, 4, 1, 0, 0);
//  float qxx = (amp.x/4.0)+0.5;
//  float sharpness = (qx.x/4.0);
//  float erosion = powr(qxx, 8);
//  float3 noise = fbm2(p + d.x*q, frequency, amplitude*powr(qxx, 4.0), lacunarity, persistence, octaves, octaveMix, sharpness, erosion);

//  float d = 8.0;
//  float2 s = warp(p + d*q, 0.3, float2(1.7, 9.2), float2(8.3, 2.8));
//  float3 terrain = fbm2(x, p, 0.1, pow(0.5*s.x+1, 2.0), 2, 0.5, so, o, octaveMix, 0.5, 0.05);// saturate(pow(mixer2.x, 4)));
//  float3 noise = fbm2(p, 0.01, 10*pow(2*q.x+1,2), 2, 0.5, o, 1, s.x, 0.8);
//  float3 noise = fbm2(p, 0.0015, 5*powr(2*q.x+1,2)+5, 2, 0.5, o, 1, 0, powr(s.y, 2));
//  float3 turbulence = fbm2(p, 0.001, 1.0, lacunarity, persistence, 3, octaveMix, 0, 0);
//  float sharpness = 0.0;//clamp(turbulence.x / 2.0, -0.8, 0.8);
//  float erosion = 0.0;//clamp(turbulence.y / 2.0, 0.0, 1.0);
////  float3 amplitudeNoise = fbm2(p, 0.0001, 1, 2, 0.5, 8, 1, 0, 0);
//  amplitude *= powr((turbulence.x / 2.0 + 1.0) / 2.0, 2.0);// saturate(powr(0.5*q.x+1.0, 2));
//  float3 noise = fbm2(p, frequency, amplitude, lacunarity, persistence, octaves, octaveMix, sharpness, erosion);

  return float4(noise.x, noise.y, -1, noise.z);
}

typedef struct {
  float2 ringCorner;
  float ringSize;
  int mStart;
  int mStop;
  int nStart;
  int nStop;
  float time;
  float3 eye;
  float4x4 mvp;
  float aspectRatio;
  bool diagnosticMode;
  int ringLevel;
} Payload;

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
  float halfCellSize;
  float ringSize;
  int level;
} Ring;

Ring corner(float2 p, int ringExponent) {
  int power = round(powr(2.0, ringExponent));
  float gridCellSize = power / 36.0;
  float halfCellSize = gridCellSize / 2.0;
  float doubleGridCellSize = 2.0 * gridCellSize;
  float ringSize = 36.0 * gridCellSize;
  float halfRingSize = 18.0 * gridCellSize;
  float2 continuousRingCorner = p - halfRingSize;
  float2 discretizedRingCorner = doubleGridCellSize * (floor(continuousRingCorner / doubleGridCellSize));
  return { discretizedRingCorner, halfCellSize, ringSize, ringExponent };
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
  float x = 0.0 + uniforms.eyeOffset.x + sin(uniforms.time/7.0) * 100;
  float z = uniforms.eyeOffset.z + uniforms.time * -10.0;
  float4 t = terrain(float2(x, z), EyeOctaves);
  float3 eye;
  if (uniforms.overheadView) {
    eye = float3(x, t.x * 2 + uniforms.eyeOffset.y, z);
  } else {
    eye = float3(x, t.x + 0.5 + uniforms.eyeOffset.y, z);
  }

  int ringExponent = gridPosition.z + uniforms.ringOffset;
  int xHalf = 0;
  int yHalf = 0;
  Ring ring = corner(eye.xz, ringExponent);
  Ring innerRing = corner(eye.xz, ringExponent - 1);
  float2 grid = abs((ring.corner + 9.0 * 2.0 * ring.halfCellSize) - innerRing.corner);
  if (grid.x < ring.halfCellSize) {
    xHalf = 1;
  }
  if (grid.y < ring.halfCellSize) {
    yHalf = 1;
  }
  
  StripRange m = stripRange(gridPosition.x, xHalf);
  StripRange n = stripRange(gridPosition.y, yHalf);
  
  float4x4 translate = matrix_translate(-eye);
  float4x4 rotate;
  if (uniforms.overheadView) {
    rotate = matrix_rotate(M_PI_F/2, float3(1.0, 0, 0));
  } else {
    rotate = matrix_rotate(M_PI_F/(12.0 + sin(uniforms.time) * 0.5), float3(sin(uniforms.time) * 2.0, cos(uniforms.time) * 2.0, 0));
  }
  float4x4 perspective = matrix_perspective(0.85, payload.aspectRatio, 0.01, 10000);
  float4x4 mvp = perspective * rotate * translate;

  payload.ringCorner = ring.corner;
  payload.ringSize = ring.ringSize;
  payload.ringLevel = ring.level;
  payload.mStart = m.start;
  payload.mStop = m.stop;
  payload.nStart = n.start;
  payload.nStop = n.stop;
  payload.time = uniforms.time;
  payload.eye = eye;
  payload.mvp = mvp;
  payload.aspectRatio = uniforms.screenWidth / uniforms.screenHeight;
  payload.diagnosticMode = uniforms.diagnosticMode;
  
  bool isCenter = gridPosition.x > 0 && gridPosition.x < gridSize.x - 1 && gridPosition.y > 0 && gridPosition.y < gridSize.y - 1;
  bool shouldRender = !isCenter || gridPosition.z == 0;
  if (threadIndex == 0 && shouldRender) {
    meshGridProperties.set_threadgroups_per_grid(uint3(Density, Density, 1));  // How many meshes to spawn per object.
  }
}

struct VertexOut {
  float4 position [[position]];
  float4 worldPosition;
  float3 worldNormal;
  simd_float3 eye;
};

struct PrimitiveOut {
  float4 colour;
  bool diagnosticMode;
  int ringLevel;
};

using TriangleMesh = metal::mesh<VertexOut, PrimitiveOut, MaxMeshletVertexCount, MaxMeshletPrimitivesCount, metal::topology::triangle>;

#define GRID_INDEX(i,j,w) ((j)*(w)+(i))
#define HLSLFMOD(x,y) ((x) - (y) * floor((x)/(y)))

[[mesh, max_total_threads_per_threadgroup(MaxTotalThreadsPerMeshThreadgroup)]]
void terrainMesh(TriangleMesh output,
                 const object_data Payload& payload [[payload]],
                 uint threadIndex [[thread_index_in_threadgroup]],
                 uint3 threadPosition [[thread_position_in_threadgroup]],
                 uint2 meshIndex [[threadgroup_position_in_grid]],
                 uint2 numThreads [[threads_per_threadgroup]],
                 uint2 numMeshes [[threadgroups_per_grid]]) {
  // Extract parameters for this particular meshlet.
  float cellSize = payload.ringSize / 36.0 / numMeshes.x; // assumes square.
  float2 corner = float2(payload.ringCorner);

  int mCells = payload.mStop - payload.mStart;
  int mStart = floor((float)meshIndex.x * (float)mCells / (float)numMeshes.x) + payload.mStart;
  int _mStop = floor((float)(meshIndex.x + 1) * (float)mCells / (float)numMeshes.x) + payload.mStart;
  int mStop = (meshIndex.x == (numMeshes.x - 1)) ? payload.mStop : _mStop;
  mStart *= numMeshes.x;
  mStop *= numMeshes.x;

  int nCells = payload.nStop - payload.nStart;
  int nStart = floor((float)meshIndex.y * (float)nCells / (float)numMeshes.y) + payload.nStart;
  int _nStop = floor((float)(meshIndex.y + 1) * (float)nCells / (float)numMeshes.y) + payload.nStart;
  int nStop = (meshIndex.y == (numMeshes.y - 1)) ? payload.nStop : _nStop;
  nStart *= numMeshes.y;
  nStop *= numMeshes.y;

  // Create mesh vertices.
  int numVertices = 0;
  for (int j = nStart; j < nStop + 1; j++) {
    for (int i = mStart; i < mStop + 1; i++) {
      float x = i * cellSize + corner.x;
      float z = j * cellSize + corner.y;

      float3 worldPos = float3(x, 0, z);
#if MORPH
      // Adjust vertices to avoid cracks.
      const float SQUARE_SIZE = cellSize;
      const float SQUARE_SIZE_4 = 4.0 * SQUARE_SIZE;

      float3 centerPosWorld = payload.eye;
      float2 offsetFromCenter = float2(abs(worldPos.x - centerPosWorld.x), abs(worldPos.z - centerPosWorld.z));
      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
      float idealSquareSize = taxicab_norm;
      float lodAlpha = idealSquareSize / (payload.ringSize / 4.0);
      const float BLACK_POINT = 0.05;
      const float WHITE_POINT = 0.25;
      lodAlpha = max((lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT), 0.0);
      const float meshScaleLerp = 0.0;  // what is this?
      lodAlpha = min(lodAlpha + meshScaleLerp, 1.0);
      
      lodAlpha = 0.0;//0.1 * (i - mStart);

//      const float BASE_DENSITY = Density * 8;
//      float3 centerPosWorld = payload.eye;
////      worldPos.xz -= HLSLFMOD(centerPosWorld.xz, 2.0 * SQUARE_SIZE); // this uses hlsl fmod, not glsl mod (sign is different).
//      float2 offsetFromCenter = float2(abs(worldPos.x - centerPosWorld.x), abs(worldPos.z - centerPosWorld.z));
//      float taxicab_norm = max(offsetFromCenter.x, offsetFromCenter.y);
//      float idealSquareSize = taxicab_norm / BASE_DENSITY;
////      float lodAlpha = fmod(payload.time, 1.0);
//      float lodAlpha = idealSquareSize / SQUARE_SIZE - 1.0;
//      const float BLACK_POINT = 0.15;
//      const float WHITE_POINT = 0.85;
//      lodAlpha = max((lodAlpha - BLACK_POINT) / (WHITE_POINT - BLACK_POINT), 0.0);
//      const float meshScaleLerp = 0.0;  // what is this?
//      lodAlpha = min(lodAlpha + meshScaleLerp, 1.0);

//      float lodY = (float)(j - nStart) / (float)(nStop - nStart);
//      float lodX = (float)(i - mStart) / (float)(mStop - mStart);
//      float lodAlpha = max(lodX, lodY);
//      lodAlpha = max(lodAlpha, 0.0);
//      const float meshScaleLerp = 0.0;  // what is this?
//      lodAlpha = min(lodAlpha + meshScaleLerp, 1.0);
//      lodAlpha = 1.0-lodAlpha;//0.0;
      
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

      float4 t = terrain(worldPos.xz, VertexOctaves);
      float y = t.x;
      float4 p(worldPos.x, y, worldPos.z, 1);
      float4 vp = payload.mvp * p;
      VertexOut out;
      out.position = vp;
      out.worldPosition = p;
      out.worldNormal = t.yzw;
      out.eye = payload.eye;
      output.set_vertex(numVertices++, out);
    }
  }

  // Create mesh edges.
  int meshVertexWidth = mStop - mStart + 1;
  int numEdges = 0;
  int numTriangles = 0;
  for (int t = nStart; t < nStop; t++) {
    for (int s = mStart; s < mStop; s++) {
      int j = t - nStart;
      int i = s - mStart;
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
        out.diagnosticMode = payload.diagnosticMode;
        out.ringLevel = payload.ringLevel;
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
  auto d = distance(in.v.eye, in.v.worldPosition.xyz);
#if FRAGMENT_NORMALS
  auto p = in.v.worldPosition;
  float maxO = FragmentOctaves;
  auto minO = 1.0;
//  auto o = min(maxO, max(minO, maxO*(pow((FragmentOctaveRange-d)/FragmentOctaveRange, 0.5))+minO));
  auto sat = saturate((FragmentOctaveRange-d)/FragmentOctaveRange);
  auto o = min(maxO, max(minO, maxO*sat + minO));
  auto t = terrain(p.xz, o);
//  auto normal = t.yzw;
//  auto normalColour = float4((normalize(normal) + 1) / 2.0, 1);
//  auto colour = normalColour;
//  return colour;
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
  float3 sun = float3(20000, 20000, 20000);
  float3 world2Sun = normalize(sun - in.v.worldPosition.xyz);
  float sunStrength = saturate(dot(n, world2Sun));

  // Make dark bits easier to see.
//  sunStrength = sunStrength * 0.9 + 0.1;
  
  float3 sunColour = float3(1.64,1.27,0.99);
  float3 lin = sunStrength;
  lin *= sunColour;
  
  float3 rock(0.55, 0.34, 0.17);
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

  if (in.p.diagnosticMode) {
    auto patchColour = in.p.colour.xyz;
    auto ringColour = float3((float)(in.p.ringLevel % 3) / 3.0, (float)(in.p.ringLevel % 4) / 4.0, (float)(in.p.ringLevel % 2) / 2.0);
    colour = mix(colour, ringColour, 0.5);
    colour = mix(colour, patchColour, 0.2);
  } else {
    float3 eye2World = normalize(in.v.worldPosition.xyz - in.v.eye);
    float3 sun2World = normalize(in.v.worldPosition.xyz - sun);
    colour = applyFog(colour, d, eye2World, sun2World);
//    colour = pow(colour, float3(1.0/2.2));
  }
  
  return float4(colour, 1.0);
}
