#include <metal_stdlib>
using namespace metal;

constant float finiteDifferenceEpsilon = 1;

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
  
  if (position.y <= terrain.waterLevel) {
    normal = float3(0, 1, 0);
    tangent = float3(1, 0, 0);
    bitangent = float3(0, 0, 1);
    return { normal, tangent, bitangent };
  } else {
    
    float d = distance(camera, position.xyz);
    float eps = clamp(finiteDifferenceEpsilon * d, finiteDifferenceEpsilon, 20.0);
    
    float3 t_pos = position;//(modelMatrix * float4(position.xyz, 1)).xyz;
    
    float2 brz = t_pos.xz + float2(eps, 0);
    float hR = terrain_height_map(brz, terrain.fractal, heightMap, noiseMap);
    
    float2 tlz = t_pos.xz + float2(0, eps);
    float hU = terrain_height_map(tlz, terrain.fractal, heightMap, noiseMap);
    
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

float terrain_fbm(float2 xz, int octaves, int warpOctaves, float frequency, float amplitude, float pw, bool ridged, texture2d<float> displacementMap) {
  if (NO_TERRAIN) {
    return 0;
  }
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
//  return amplitude;
  if (ridged) {
    float ridge_height = amplitude;
    float hdisp = displacement - ridge_height;
    return ridge_height - sqrt(hdisp*hdisp+200);  // Smooth the tops of ridges.
  }
  return displacement;
}

float multi_terrain(float2 xz, int octaves, float frequency, float amplitude, bool ridged, texture2d<float> displacementMap) {
  
//  float3 p = float3(xz.x, 0, xz.y);
//  return simplex_3d(p / 10000).x * amplitude;
//  float dp = displacementMap.sample(displacement_sample, xz * frequency / 2).r;
//  float k = 0.67;
//  float m = smoothstep(k, k+0.02, dp);
  float a = 0;
//  float b = 0;
//  if (m < 1.0) {
  // one way to warp https://www.iquilezles.org/www/articles/warp/warp.htm
  int warp_octaves = 2;
  float2 wxz = float2(terrain_fbm(xz, warp_octaves, 0, frequency, amplitude, 1, false, displacementMap),
                      terrain_fbm(xz + float2(5.2, 1.3), warp_octaves, 0, frequency, amplitude, 1, false, displacementMap));
//    float2 wxz2 = terrain_fbm(xz + 2*wxz, 3, 0, frequency, amplitude, 1, false, displacementMap);
  a = terrain_fbm(xz + 6*wxz, octaves, 0, frequency, amplitude, 1, true, displacementMap);
//  }
//  if (m > 0.0) {
//    b = terrain_fbm(xz, octaves2, 0, frequency * 10, amplitude / 10, 5, false, displacementMap);
//  }
//  return mix(a, b, m);
  return a;
}



float calc_distance(float3 pointA, float3 pointB, float3 camera_position) {
  float3 midpoint = (pointA + pointB) * 0.5;
  return distance_squared(camera_position, midpoint);
}

float3 find_unit_spherical_for_template(float3 p, float r, float R, float d) {
  float h = sqrt(powr(d, 2) - powr(r, 2));
  float s = sqrt(powr(R, 2) - powr(r, 2));
  
  float zs = (powr(R, 2) + powr(d, 2) - powr(h+s, 2)) / (2 * r * (h+s));
  
  float3 z = float3(0.0, zs, 0.0);
  float3 g = p;
  float n = 4;
  g.y = (1 - powr(g.x, n)) * (1 - powr(g.z, n));
  float3 gp = g + z;
  float mgp = length(gp);
  float3 vector = gp / mgp;
  
  return vector;
  
//  float3 b = float3(0, 0.1002310, 0.937189); // TODO: this has to be linearly independent of eye.
//  float3 w = eye / length(eye);
//  float3 wb = cross(w, b);
//  float3 v = wb / length(wb);
//  float3 u = cross(w, v);
  //    float3x3 rotation = transpose(float3x3(u, v, w));
  
  //    float3 rotated = vector * rotation;
  //    return rotated;
}

float3 sphericalise(float sphere_radius, float3 tp, float2 cp) {
//  return tp;
  if (sphere_radius > 0) {
    float3 w = normalize(tp + float3(-cp.x, sphere_radius, -cp.y));
    float3 pp = w * (sphere_radius + tp.y);
    pp = pp - float3(-cp.x, 0, -cp.y);
    return pp;
  } else {
    return tp;
  }
}

float4 intersectionWithNearPlane(float4 v1, float4 v2, float near) {
  float x1 = v1.x;
  float x2 = v2.x;
  float y1 = v1.y;
  float y2 = v2.y;
  float z1 = v1.z;
  float z2 = v2.z;
  
  float n = (v1.w - near) / (v1.w - v2.w);
  float xc = (n * x1) + ((1-n) * x2);
  float yc = (n * y1) + ((1-n) * y2);
  float zc = (n * z1) + ((1-n) * z2);
  float wc = near;

  return float4(xc, yc, zc, wc);
}


// TODO, need to adjust for sphere mapping
//      if (useShadows) {
//        float d = distance_squared(uniforms.cameraPosition, position);
//
//        // TODO Some bug here when sun goes under the world.
//        float3 origin = position;
//
//        float max_dist = 1000;
//
//        float min_step_size = clamp(d, 1.0, 50.0);
//        float step_size = min_step_size;
//        for (float d = step_size; d < max_dist; d += step_size) {
//          float3 tp = origin + L * d;
//          if (tp.y > terrain.height) {
//            break;
//          }
//
//          float height = sample_terrain(tp.xz, terrain.fractal, heightMap, noiseMap, true);
//          if (height > tp.y) {
//            shadowed = diffuseIntensity;
//            break;
//          }
//          min_step_size *= 2;
//          step_size = max(min_step_size, (tp.y - height)/2);
//        }
//      }
