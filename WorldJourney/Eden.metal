#include <metal_stdlib>
#include <simd/simd.h>
#include "Common.h"
#include "ValueNoise.h"

using namespace metal;

constant bool useShadows = false;
constant bool useNormalMaps = true;
constant float3 ambientIntensity = 0.15;
constant float3 lightColour(1.0);
//constant float waterLevel = -1000000;
constant int minTessellation = 1;
constant float finiteDifferenceEpsilon = 1;

constexpr sampler displacement_sample(coord::normalized, address::repeat, filter::linear);

float terrain_fbm(float2 xz, int octaves, int warpOctaves, float frequency, float amplitude, float pw, bool ridged, texture2d<float> displacementMap) {
  float persistence = 0.4;
  float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
  float a = amplitude;
  float displacement = 0.0;
  float2 p = xz * frequency;
  for (int i = 0; i < octaves; i++) {
    p = m * p;
    float2 wp = p;
    if (i < warpOctaves) {
      wp = float2(displacementMap.sample(displacement_sample, wp.xy).r, displacementMap.sample(displacement_sample, wp.yx).r) / 20;
    }
    float v = displacementMap.sample(displacement_sample, wp).r;
    v = pow(v, pw);
    v = v * a;
//    if (i > 5) {
//      v = v * sqrt(displacement);
//    }
    displacement += v;
    a *= persistence;
  }
  if (ridged) {
    float ridge_height = amplitude;
    float hdisp = displacement - ridge_height;
    return ridge_height - sqrt(hdisp*hdisp+200);  // Smooth the tops of ridges.
  }
  return displacement;
}

float multi_terrain(float2 xz, int octaves, float frequency, float amplitude, bool ridged, texture2d<float> displacementMap, bool fast) {
  float dp = displacementMap.sample(displacement_sample, xz * frequency / 2).r;
  float m = smoothstep(0.45, 0.55, dp);
  float a = 0;
  float b = 0;
  if (m < 1.0) {
    // TODO: fast option is not making useful normals.
    int octaves2 = 4;// fast ? 4 : 4;
    a = terrain_fbm(xz, octaves2, 2, frequency, amplitude, 2, true, displacementMap);
  }
  if (m > 0.0) {
    int octaves2 = 2;// fast ? 3 : 3;
    b = terrain_fbm(xz, octaves2, 0, frequency * 10, amplitude / 10, 5, false, displacementMap);
  }
  return mix(a, b, m);
//  return b;
}

float terrain_height_map(float2 xz, Fractal fractal, texture2d<float> heightMap, texture2d<float> displacementMap, bool fast) {
//  constexpr sampler height_sample(coord::normalized, address::clamp_to_zero, filter::linear);
  float height = 0;//heightMap.sample(height_sample, xz / 100000).r * TERRAIN_HEIGHT;
//  return height;
  float displacement = multi_terrain(xz, fractal.octaves, fractal.frequency, fractal.amplitude, true, displacementMap, fast);
  float total = height + displacement;
  return clamp(total, 0., fractal.amplitude);
}

struct TerrainNormal {
  float3 normal;
  float3 tangent;
  float3 bitangent;
};

TerrainNormal terrain_normal(float3 position,
                             float3 camera,
                             float4x4 modelMatrix,
                             float scale,
                             Terrain terrain,
                             texture2d<float> heightMap,
                             texture2d<float> noiseMap) {
  float3 normal;
  float3 tangent;
  float3 bitangent;
  
//  if (position.y <= waterLevel) {
//    normal = float3(0, 1, 0);
//    tangent = float3(1, 0, 0);
//    bitangent = float3(0, 0, 1);
//  return { normal, tangent, bitangent };
//  } else {
    
    float d = distance(camera, position.xyz);
    float eps = clamp(finiteDifferenceEpsilon * d, finiteDifferenceEpsilon, 20.0);
    
    float3 t_pos = (modelMatrix * float4(position.xyz, 1)).xyz;
    
    float2 brz = t_pos.xz + float2(eps, 0);
    float hR = terrain_height_map(brz, terrain.fractal, heightMap, noiseMap, true);
    
    float2 tlz = t_pos.xz + float2(0, eps);
    float hU = terrain_height_map(tlz, terrain.fractal, heightMap, noiseMap, true);
    
    tangent = normalize(float3(eps, position.y - hR, 0));
    
    bitangent = normalize(float3(0, position.y - hU, eps));
    
    normal = normalize(float3(position.y - hR, eps, position.y - hU));
//  }
  
  return {
    .normal = normal,
    .tangent = tangent,
    .bitangent = bitangent
  };
}



/** height kernel */

kernel void eden_height(texture2d<float> heightMap [[texture(0)]],
                        texture2d<float> noiseMap [[texture(1)]],
                        constant Uniforms &uniforms [[buffer(0)]],
                        constant Terrain &terrain [[buffer(1)]],
                        constant float2 &xz [[buffer(2)]],
                        volatile device float *height [[buffer(3)]],
                        volatile device float3 *normal [[buffer(4)]],
                        uint gid [[thread_position_in_grid]]) {
  float2 axz = (uniforms.modelMatrix * float4(xz.x, 0, xz.y, 1)).xz;
  float y = terrain_height_map(xz, terrain.fractal, heightMap, noiseMap, false);
  float3 p = float3(axz.x, y, axz.y);
  TerrainNormal n = terrain_normal(p, p, uniforms.modelMatrix, uniforms.scale, terrain, heightMap, noiseMap);
  *height = y;
  *normal = n.normal;
}



/** tessellation kernel */

float calc_distance(float3 pointA, float3 pointB, float3 camera_position) {
  float3 midpoint = (pointA + pointB) * 0.5;
  return distance_squared(camera_position, midpoint);
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
    
    float2 pA = (uniforms.modelMatrix * float4(control_points[pointAIndex + index], 1)).xz;
    float aH = terrain_height_map(pA, terrain.fractal, heightMap, noiseMap, true);
    float3 pointA = float3(pA.x, aH, pA.y);
    
    float2 pB = (uniforms.modelMatrix * float4(control_points[pointBIndex + index], 1)).xz;
    float bH = terrain_height_map(pB, terrain.fractal, heightMap, noiseMap, true);
    float3 pointB = float3(pB.x, bH, pB.y);
    
//    float3 camera = uniforms.cameraPosition;
//
//    float d = calc_distance(pointA,
//                            pointB,
//                            camera);
//    float numer = 256 * uniforms.scale;
//    float denom = (d);// / (uniforms.scale * uniforms.scale));
//    float stepped = (numer)/(denom);
////    float stepped = exp(-0.000001*pow(d, 1.95));
////    float stepped = pow( 4.0*d*(1.0-d), 10 );
////    float stepped = 2-exp(d/1);
//    float tessellation = minTessellation + saturate(stepped) * (terrain.tessellation - minTessellation);
        
    float4x4 vpMatrix = uniforms.projectionMatrix * uniforms.viewMatrix;
    float4 projectedA = vpMatrix * float4(pointA, 1);
    float4 projectedB = vpMatrix * float4(pointB, 1);
    
    float aw = projectedA.w;
    float bw = projectedB.w;
    float2 screenA = projectedA.xy / aw;
    float2 screenB = projectedB.xy / bw;
    screenA.x = (screenA.x + 1.0) / 2.0 * uniforms.screenWidth;
    screenA.y = (screenA.y + 1.0) / 2.0 * uniforms.screenHeight;
    screenB.x = (screenB.x + 1.0) / 2.0 * uniforms.screenWidth;
    screenB.y = (screenB.y + 1.0) / 2.0 * uniforms.screenHeight;

    float screenLength = distance(screenA, screenB);
    
//    float minSide = 3;
//    float maxSide = 10;
//    float sideLength = maxSide - (1.0/d) * (maxSide - minSide);
    
    float tessellation = screenLength / TESSELLATION_SIDELENGTH;
//    tessellation = pow(2.0, ceil(log2(tessellation)));
    
    tessellation = clamp(tessellation, (float)minTessellation, (float)terrain.tessellation);
    
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
  float height;
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
  float3 positionp = (uniforms.modelMatrix * float4(position, 1)).xyz;
  float h = terrain_height_map(positionp.xz, terrain.fractal, heightMap, noiseMap, false);
  position.y = h;
  positionp.y = h;
  
  TerrainNormal sample = terrain_normal(position.xyz, uniforms.cameraPosition, uniforms.modelMatrix, uniforms.scale, terrain, heightMap, noiseMap);
  
  float3 pp = positionp;
  
  if (SPHERE_RADIUS > 0) {
    float3 tp = pp;
    float2 cp = uniforms.cameraPosition.xz;
    float3 w = normalize(tp + float3(-cp.x, SPHERE_RADIUS, -cp.y));
    pp = w * (SPHERE_RADIUS + h);
    pp = pp - float3(-cp.x, SPHERE_RADIUS, -cp.y);
  }

  // TODO: need to warp normals around sphere too (?)
  float3 normal = sample.normal;
  float3 tangent = sample.tangent;
  float3 bitangent = sample.bitangent;
  
  float4 clipPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(pp, 1);
  
  return {
    .clipPosition = clipPosition,
    .height = h,
    .worldPosition = pp,
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
  
//  if (in.worldPosition.y < waterLevel+1) {
//    out.position = float4(in.worldPosition.x, waterLevel, in.worldPosition.z, (float)in.height / (float)TERRAIN_HEIGHT);
//    out.albedo = float4(.098, .573, .80, 1);
//  } else {
    out.position = float4(in.worldPosition, (float)in.height / (float)TERRAIN_HEIGHT);
    out.albedo = float4(1, 1, 1, 0.4);
//  }
  
  float3 n = in.worldNormal;

  if (useNormalMaps) {
    
    constexpr sampler normal_sample(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    
    float2 xz = in.worldPosition.xz;
    
    float3 distantNormalMapValue = groundNormalMap.sample(normal_sample, xz / 2000).xyz * 2.0 - 1.0;

    float3 mediumNormalMapValue = groundNormalMap.sample(normal_sample, xz / 200).xyz * 2.0 - 1.0;
    
    float3 closeNormalMapValue = groundNormalMap.sample(normal_sample, xz / 2).xyz * 2.0 - 1.0;
    
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
  
  float2 v_texCoord = in.uv;
  float2 uv = v_texCoord;

  float4 albedo = albedoTexture.sample(sample, uv);
  
  float4 ptex = positionTexture.sample(sample, uv);
  float3 position = ptex.xyz;
  float raw_height = ptex.a * TERRAIN_HEIGHT;
  
  float2 uvn = uv - float2(0.5);
  float aspect = albedoTexture.get_width() / albedoTexture.get_height();
  uvn.x *= aspect;
  //TODO sun is not quite in the right position...
  float4 pmatrix = float4(normalize(float3(uvn.x, -uvn.y, -0.9)), 1);
  float3 cameraDirection = normalize((transpose(uniforms.viewMatrix) * pmatrix).xyz);

  float3 sky_color = float3(0xE3/255.0, 0x9E/255.0, 0x50/255.0);
  
  float atmosphere_transition_edge = 10000.0;
  float atmosphere_thickness = 20000.0;
  float atmosphereness = smoothstep(atmosphere_transition_edge, atmosphere_thickness, uniforms.cameraPosition.y);
  
  float3 sun_colour = float3(0xFB/255.0, 0xFC/255.0, 0xCD/255.0);
  float3 light_dir = normalize(-uniforms.lightDirection);
  float samesame = dot(cameraDirection, light_dir);
  float3 scene_color = mix(sky_color, float3(0, 0, 0), atmosphereness);
  scene_color = mix(scene_color, sun_colour, saturate(pow(samesame, 100)));

  if (albedo.a > 0.1) {
    
    float3 normal = normalTexture.sample(sample, uv).xyz;
    
    if (uniforms.renderMode == 1) {
      scene_color = normal;
    } else if (uniforms.renderMode == 2) {
      float height = raw_height / TERRAIN_HEIGHT;
      float3 height_colour = float3(0.2, 0.0, height);
      scene_color = height_colour;
    } else {

      float3 L = light_dir;
      
      if (albedo.a < 0.5) {
        float3 rock = float3(0x96/255.0, 0x59/255.0, 0x2F/255.0);
        float3 snow = float3(1);
//        float3 grass = float3(.663, .80, .498);
        float3 ground = rock;
        float3 cliff = rock;

        float flatness = dot(normal, float3(0, 1, 0));

        float stepped = smoothstep(0.85, 1.0, flatness);
        float plainstep = smoothstep(1100, 1300, raw_height);
        float3 plain = mix(ground, snow, plainstep);
        float3 c = mix(cliff, plain, stepped);
        c = mix(c, sky_color, atmosphereness/2);
//        c = float3(1);
        albedo = float4(c, 1);
      }
      
      float diffuseIntensity = saturate(dot(normal, L));
      
      float3 specularColor = 0;
      float materialShininess = 256;
      float3 materialSpecularColor = float3(1, 1, 1);
      
      float3 cameraDirection = normalize(position - uniforms.cameraPosition);
      
//      if (diffuseIntensity > 0 && raw_height < waterLevel+1) {
//        float3 reflection = reflect(L, normal);
//        float specularIntensity = pow(saturate(dot(reflection, cameraDirection)), materialShininess);
//        specularColor = lightColour * materialSpecularColor * specularIntensity;
//      }
      
      float3 shadowed = 0.0;
      
      // TODO, need to adjust for sphere mapping
      if (useShadows) {
        float d = distance_squared(uniforms.cameraPosition, position);
        
        // TODO Some bug here when sun goes under the world.
        float3 origin = position;
        
        float max_dist = 1000;
        
        float min_step_size = clamp(d, 1.0, 50.0);
        float step_size = min_step_size;
        for (float d = step_size; d < max_dist; d += step_size) {
          float3 tp = origin + L * d;
          if (tp.y > terrain.height) {
            break;
          }
          
          float height = terrain_height_map(tp.xz, terrain.fractal, heightMap, noiseMap, true);
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
