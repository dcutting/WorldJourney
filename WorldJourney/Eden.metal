#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "ValueNoise.h"

using namespace metal;

constant bool useShadows = false;
constant bool useNormalMaps = true;
constant bool useDisplacementMaps = false;
constant float3 ambientIntensity = 0.05;
constant float3 lightColour(1.0);
constant float waterLevel = -1;
constant int minTessellation = 1;
constant float finiteDifferenceEpsilon = 1;
constant float octaves = 8;


float2 normalise_point(float2 xz, Terrain terrain) {
  return (xz + terrain.size / 2.0) / terrain.size;
}

float terrain_fbm(float2 xz, float frequency, float amplitude, texture2d<float> displacementMap) {
  constexpr sampler displacement_sample(coord::normalized, address::repeat, filter::linear);
  float persistence = 0.4;
  float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
  float a = amplitude;
  float displacement = 0.0;
  float2 p = xz * frequency;
  for (int i = 0; i < octaves; i++) {
    p = m * p;
    displacement += displacementMap.sample(displacement_sample, p).r * a;
    a *= persistence;
  }
  return (TERRAIN_HEIGHT / 2.0) - abs(displacement - TERRAIN_HEIGHT / 2.0);
}

float terrain_height_map(float2 xz, float maxHeight, texture2d<float> heightMap, texture2d<float> displacementMap) {
//  constexpr sampler height_sample(coord::normalized, address::clamp_to_zero, filter::linear);
  float height = 0;//heightMap.sample(height_sample, xz).r * maxHeight * 0.5;
  float displacement = terrain_fbm(xz, 0.1, maxHeight * 0.8, displacementMap);
  float total = height + displacement;
  return clamp(total, waterLevel, maxHeight);
}

struct TerrainNormal {
  float3 normal;
  float3 tangent;
  float3 bitangent;
};

TerrainNormal terrain_normal(float3 position,
                             float3 camera,
                             Terrain terrain,
                             texture2d<float> heightMap,
                             texture2d<float> noiseMap) {
  float3 normal;
  float3 tangent;
  float3 bitangent;
  
  if (position.y <= waterLevel) {
    normal = float3(0, 1, 0);
    tangent = float3(1, 0, 0);
    bitangent = float3(0, 0, 1);
  } else {
    
    float d = distance(camera, position.xyz);
    float eps = clamp(finiteDifferenceEpsilon * d, finiteDifferenceEpsilon, 50.0);
    
    float3 t_pos = position.xyz;
    
    float2 br = t_pos.xz + float2(eps, 0);
    float2 brz = normalise_point(br, terrain);
    float hR = terrain_height_map(brz, terrain.height, heightMap, noiseMap);
    
    float2 tl = t_pos.xz + float2(0, eps);
    float2 tlz = normalise_point(tl, terrain);
    float hU = terrain_height_map(tlz, terrain.height, heightMap, noiseMap);
    
    tangent = normalize(float3(eps, position.y - hR, 0));
    
    bitangent = normalize(float3(0, position.y - hU, eps));
    
    normal = normalize(float3(position.y - hR, eps, position.y - hU));
  }
  
  return {
    .normal = normal,
    .tangent = tangent,
    .bitangent = bitangent
  };
}



/** height kernel */

kernel void eden_height(texture2d<float> heightMap [[texture(0)]],
                        texture2d<float> noiseMap [[texture(1)]],
                        constant Terrain &terrain [[buffer(0)]],
                        constant float2 &xz [[buffer(1)]],
                        volatile device float *height [[buffer(2)]],
                        volatile device float3 *normal [[buffer(3)]],
                        uint gid [[thread_position_in_grid]]) {
  
  float2 axz = normalise_point(xz, terrain);
  float y = terrain_height_map(axz, terrain.height, heightMap, noiseMap);
  float3 p = float3(xz.x, y, xz.y);
  TerrainNormal n = terrain_normal(p, p, terrain, heightMap, noiseMap);
  *height = y;
  *normal = n.normal;
}



/** tessellation kernel */

float calc_distance(float3 pointA, float3 pointB, float3 camera_position) {
  float3 midpoint = (pointA + pointB) * 0.5;
  return distance(camera_position, midpoint);
}

kernel void eden_tessellation(constant float *edge_factors [[buffer(0)]],
                              constant float *inside_factors [[buffer(1)]],
                              device MTLQuadTessellationFactorsHalf *factors [[buffer(2)]],
                              constant float3 *control_points [[buffer(3)]],
                              constant Uniforms &uniforms [[buffer(4)]],
                              constant Terrain &terrain [[buffer(5)]],
                              texture2d<float> heightMap [[texture(0)]],
                              texture2d<float> noiseMap [[texture(1)]],
                              uint pid [[thread_position_in_grid]]) {
  
  uint index = pid * 4;
  float totalTessellation = 0;
  for (int i = 0; i < 4; i++) {
    int pointAIndex = i;
    int pointBIndex = i + 1;
    if (pointAIndex == 3) {
      pointBIndex = 0;
    }
    int edgeIndex = pointBIndex;
    
    float2 pA1 = (uniforms.modelMatrix * float4(control_points[pointAIndex + index], 1)).xz;
    float2 pA = normalise_point(pA1, terrain);
    float aH = terrain_height_map(pA, terrain.height, heightMap, noiseMap);
    float3 pointA = float3(pA1.x, aH, pA1.y);
    
    float2 pB1 = (uniforms.modelMatrix * float4(control_points[pointBIndex + index], 1)).xz;
    float2 pB = normalise_point(pB1, terrain);
    float bH = terrain_height_map(pB, terrain.height, heightMap, noiseMap);
    float3 pointB = float3(pB1.x, bH, pB1.y);
    
    float3 camera = uniforms.cameraPosition;
    
    float cameraDistance = calc_distance(pointA,
                                         pointB,
                                         camera);
    float stepped = PATCH_GRANULARITY / (cameraDistance * 2);
    float tessellation = minTessellation + stepped * (terrain.tessellation - minTessellation);
    factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
    totalTessellation += tessellation;
  }
  factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
  factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}



/** vertex shader */

struct ControlPoint {
  float4 position [[attribute(0)]];
};

struct EdenVertexOut {
  float4 clipPosition [[position]];
  float3 worldPosition;
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
};

[[patch(quad, 4)]]
vertex EdenVertexOut eden_vertex(patch_control_point<ControlPoint>
                                 control_points [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]],
                                 constant Terrain &terrain [[buffer(2)]],
                                 texture2d<float> heightMap [[texture(0)]],
                                 texture2d<float> noiseMap [[texture(1)]],
                                 texture2d<float> groundNormalMap [[texture(2)]],
                                 uint patchID [[patch_id]],
                                 float2 patch_coord [[position_in_patch]]) {
  
  float u = patch_coord.x;
  float v = patch_coord.y;
  
  float2 top = mix(control_points[0].position.xz,
                   control_points[1].position.xz, u);
  float2 bottom = mix(control_points[3].position.xz,
                      control_points[2].position.xz, u);
  
  float2 interpolated = mix(top, bottom, v);
  
  float3 position = float3(interpolated.x, 0.0, interpolated.y);
  float2 xz = normalise_point(position.xz, terrain);
  position.y = terrain_height_map(xz, terrain.height, heightMap, noiseMap);
  
  TerrainNormal sample = terrain_normal(position.xyz, uniforms.cameraPosition, terrain, heightMap, noiseMap);
  
  float3 normal = sample.normal;
  float3 tangent = sample.tangent;
  float3 bitangent = sample.bitangent;
  
  if (useDisplacementMaps) {
  
    constexpr sampler normal_sample(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    
    float3 normalMapValue = normalize(groundNormalMap.sample(normal_sample, position.xz / 2).xyz * 2.0 - 1.0);

    float3 displaced = sample.normal * normalMapValue.z + sample.tangent * normalMapValue.x + sample.bitangent * normalMapValue.y;
    
    position += displaced * 0.1;
  }
  
  float4 clipPosition = uniforms.mvpMatrix * float4(position, 1);
  
  return {
    .clipPosition = clipPosition,
    .worldPosition = position,
    .worldNormal = normal,
    .worldTangent = tangent,
    .worldBitangent = bitangent
  };
}



/** gbuffer fragment shader */

struct GbufferOut {
  float4 albedo [[color(0)]];
  float4 normal [[color(1)]];
  float4 position [[color(2)]];
};

fragment GbufferOut gbuffer_fragment(EdenVertexOut in [[stage_in]],
                                     texture2d<float> cliffNormalMap [[texture(0)]],
                                     texture2d<float> groundNormalMap [[texture(1)]],
                                     constant Uniforms &uniforms [[buffer(0)]]) {
  GbufferOut out;
  
  if (in.worldPosition.y < waterLevel+1) {
    out.position = float4(in.worldPosition.x, waterLevel, in.worldPosition.z, 1);
    out.albedo = float4(.098, .573, .80, 1);
  } else {
    out.position = float4(in.worldPosition, 1.0);
    out.albedo = float4(1, 1, 1, 0.4);
  }
  
  float3 n = in.worldNormal;

  if (useNormalMaps) {
    
    constexpr sampler normal_sample(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    
    float3 distantNormalMapValue = groundNormalMap.sample(normal_sample, in.worldPosition.xz / 2000).xyz * 2.0 - 1.0;

    float3 mediumNormalMapValue = groundNormalMap.sample(normal_sample, in.worldPosition.xz / 200).xyz * 2.0 - 1.0;
    
    float3 closeNormalMapValue = groundNormalMap.sample(normal_sample, in.worldPosition.xz / 2).xyz * 2.0 - 1.0;
    
    float3 normalMapValue = normalize(closeNormalMapValue * 0.5 + mediumNormalMapValue * 0.3 + distantNormalMapValue * 0.2);

    n = n * normalMapValue.z + in.worldTangent * normalMapValue.x + in.worldBitangent * normalMapValue.y;
  }
  
  out.normal = float4(normalize(n), 1);
  
  return out;
}



/** composition vertex shader */

struct CompositionOut {
  float4 position [[position]];
  float2 uv;
};

vertex CompositionOut composition_vertex(constant float2 *vertices [[buffer(0)]],
                                         constant float2 *uv [[buffer(1)]],
                                         uint id [[vertex_id]]) {
  return {
    .position = float4(vertices[id], 0.0, 1.0),
    .uv = uv[id]
  };
}



/** composition fragment shader */

fragment float4 composition_fragment(CompositionOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]],
                                     constant Terrain &terrain [[buffer(1)]],
                                     texture2d<float> albedoTexture [[texture(0)]],
                                     texture2d<float> normalTexture [[texture(1)]],
                                     texture2d<float> positionTexture [[texture(2)]],
                                     texture2d<float> rockTexture [[texture(3)]],
                                     texture2d<float> heightMap [[texture(5)]],
                                     texture2d<float> noiseMap [[texture(6)]],
                                     texture2d<float> normalMap [[texture(7)]],
                                     texturecube<float> skyTexture [[texture(8)]]) {
  
  constexpr sampler sample(min_filter::linear, mag_filter::linear);
  
  float4 albedo = albedoTexture.sample(sample, in.uv);
  
  float3 position = positionTexture.sample(sample, in.uv).xyz;
  
  float2 uvn = in.uv - float2(0.5);
  float aspect = albedoTexture.get_width() / albedoTexture.get_height();
  uvn.x *= aspect;
  //TODO sun is not quite in the right position...
  float4 pmatrix = float4(normalize(float3(uvn.x, -uvn.y, -0.9)), 1);
  float3 cameraDirection = normalize((transpose(uniforms.viewMatrix) * pmatrix).xyz);

  float3 scene_color = float3(0, 0, 0);// 191.0/255.0, 1) * 0.8;//.529, .808, .922);
  
  // get the light direction
  float3 light_dir = normalize(-uniforms.lightDirection);
  
  float samesame = dot(cameraDirection, light_dir);
  scene_color = mix(scene_color, float3(1), saturate(pow(samesame, 1000)));
//  scene_color.xyz = cameraDirection;
  
//  scene_color = skyTexture.sample(sample, cameraDirection).xyz;

  if (albedo.a > 0.1) {
    
    float3 normal = normalTexture.sample(sample, in.uv).xyz;
    
    if (uniforms.renderNormals) {
      scene_color = normal;
    } else {

      float3 L = light_dir;// normalize(uniforms.lightPosition - position);
      
      if (albedo.a < 0.5) {
        //      float flatness = dot(normal, float3(0, 1, 0));
        //        float ds = distance_squared(uniforms.cameraPosition, position) / ((terrain.size * terrain.size));
        //        float3 rockFar = float3(0x75/255.0, 0x5D/255.0, 0x43/255.0);//rockTexture.sample(repeat_sample, position.xz / 100).xyz;
        //        float3 rockClose = rockTexture.sample(repeat_sample, position.xz / 10).xyz;
        //        float3 rock = mix(rockClose, rockFar, saturate(ds * 1000));
        //      float3 rock = float3(0.6, 0.3, 0.2);
        //      float3 snow = float3(1);
        
        //      float3 grass = float3(.663, .80, .498);
        //      float stepped = smoothstep(0.65, 1.0, flatness);
        //      float3 plain = position.y > 200 ? snow : grass;
        float3 c = float3(1);// mix(rock, plain, stepped);
        albedo = float4(c, 1);
      }
      
      float diffuseIntensity = saturate(dot(normal, L));
      
      float3 specularColor = 0;
      float materialShininess = 256;
      float3 materialSpecularColor = float3(1, 1, 1);
      
      float3 cameraDirection = normalize(position - uniforms.cameraPosition);
      
      if (diffuseIntensity > 0 && position.y < waterLevel+1) {
        float3 reflection = reflect(L, normal);
        float specularIntensity = pow(saturate(dot(reflection, cameraDirection)), materialShininess);
        specularColor = lightColour * materialSpecularColor * specularIntensity;
      }
      
      float3 shadowed = 0.0;
      
      if (useShadows) {
        float d = distance_squared(uniforms.cameraPosition, position);
        
        // TODO Some bug here when sun goes under the world.
        float3 origin = position;
        
        float max_dist = TERRAIN_SIZE;
        
        float min_step_size = clamp(d, 1.0, 50.0);
        float step_size = min_step_size;
        for (float d = step_size; d < max_dist; d += step_size) {
          float3 tp = origin + L * d;
          if (tp.y > terrain.height) {
            break;
          }
          
          float2 xz = normalise_point(tp.xz, terrain);
          float height = terrain_height_map(xz, terrain.height, heightMap, noiseMap);
          if (height > tp.y) {
            shadowed = diffuseIntensity;
            break;
          }
          min_step_size *= 2;
          step_size = max(min_step_size, (tp.y - height)/2);
        }
      }
      
      scene_color = saturate(ambientIntensity + diffuseIntensity - shadowed + specularColor) * lightColour * albedo.xyz;
    }
  }
  
  return float4(scene_color, 1.0);
}
