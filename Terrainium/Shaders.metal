#include <metal_stdlib>
#include "Common.h"
#include "../WorldJourney/Maths.h"
#include "../WorldJourney/WorldTerrain.h"

using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float3 unitPositionLod;
  float3 worldPositionLod;
  float4 noise;
  vector_int3 cubeOrigin;
  int cubeSize;
  float3 cubeInner;
  int tier;
};

struct ControlPoint {
  float4 position [[attribute(0)]];
};

//vertex VertexOut terrainium_vertex(constant float2 *vertices [[buffer(0)]],
//                                   constant Uniforms &uniforms [[buffer(1)]],
//                                   constant QuadUniforms *quadUniforms [[buffer(2)]],
//                                   uint id [[vertex_id]],
//                                   ushort iid [[instance_id]]
//                                   ) {
//  float2 vid = vertices[id];
//  float4 v;
//  switch (uniforms.side) {  // TODO: make this a compile-time parameter.
//    case 0: // top
//    case 3: // bottom
//      v = float4(vid.x, 0, vid.y, 1.0);
//      break;
//    case 1: // front
//    case 4: // back
//      v = float4(0, vid.x, vid.y, 1.0);
//      break;
//    case 2: // left
//    case 5: // right
//      v = float4(vid.x, vid.y, 0, 1.0);
//      break;
//  }

constant int minOctaves = 2;
constant int maxOctaves = 23;
constant float minDist = 64.0;
constant float maxDist = 524288;

[[patch(quad, 4)]]
vertex VertexOut terrainium_vertex(patch_control_point<ControlPoint> control_points [[stage_in]],
                                   ushort iid [[instance_id]],
                                   uint patchID [[patch_id]],
                                   float2 patch_coord [[position_in_patch]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   constant QuadUniforms *quadUniforms [[buffer(2)]]
                                   ) {
  float patchu = patch_coord.x;
  float patchv = patch_coord.y;
  float2 top = mix(control_points[0].position.xy, control_points[1].position.xy, patchu);
  float2 bottom = mix(control_points[3].position.xy, control_points[2].position.xy, patchu);
  float2 vid = mix(top, bottom, patchv);
  float4 v = float4(vid.x, 0, vid.y, 1.0);

  float3 dp = (quadUniforms[iid].m * v).xyz;
  float dist = distance(dp, uniforms.eyeLod);
  float oct = adaptiveOctaves(dist, minOctaves, maxOctaves, minDist/uniforms.lod, maxDist/uniforms.lod, 4);
  
  float3 cubeInner = v.xyz;
  float4 noise = sampleInf(quadUniforms[iid].cubeOrigin, quadUniforms[iid].cubeSize, cubeInner, uniforms.amplitudeLod, oct, 0);

  v.y = (noise.x / quadUniforms[iid].scale / uniforms.radiusLod);

  float4 p = quadUniforms[iid].mvp * v;
  float3 wp = (quadUniforms[iid].m * v).xyz;

  return {
    .position = p,
//    .unitPositionLod = float3(0),//wp3,
    .worldPositionLod = wp,
    .noise = noise,
    .cubeOrigin = quadUniforms[iid].cubeOrigin,
    .cubeSize = quadUniforms[iid].cubeSize,
    .cubeInner = cubeInner,
    .tier = quadUniforms[iid].tier
  };
}

float3 applyFog(float3  rgb,      // original color of the pixel
                float distance,   // camera to point distance
                float3  rayDir,   // camera to point vector
                float3  sunDir )  // sun light direction
{
  float b = 0.001;
  float fogAmount = 1.0 - exp( -distance*b );
  float sunAmount = max( dot( rayDir, sunDir ), 0.0 );
  float3  fogColor  = mix( float3(0.5,0.6,0.7), // bluish
                          float3(1.0,0.9,0.7), // yellowish
                          pow(sunAmount,8.0) );
  return mix( rgb, fogColor, fogAmount );
}

//#define FINITE_DIFFERENCES 1
//#define FRAGMENT_NORMALS 1

fragment float4 terrainium_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
  float dist = distance(in.worldPositionLod, uniforms.eyeLod);
  float o = adaptiveOctaves(dist, minOctaves, maxOctaves, minDist/uniforms.lod, maxDist/uniforms.lod, 0.14);
//#if FINITE_DIFFERENCES
//  float epsilon = 0.01;
//  float4 noiseX = sampleInf(in.cubeOrigin, in.cubeSize, in.cubeInner + float3(epsilon, 0, 0), uniforms.amplitudeLod, o);
//  float pX = noiseX.x;// * uniforms.amplitudeLod;// / in.cubeSize;
//  float4 noiseZ = sampleInf(in.cubeOrigin, in.cubeSize, in.cubeInner + float3(0, 0, epsilon), uniforms.amplitudeLod, o);
//  float pZ = noiseZ.x;// * uniforms.amplitudeLod;// / in.cubeSize;
//
//  float dx = (pX - in.noise.x)/epsilon;
//  float dz = (pZ - in.noise.x)/epsilon;
//
//  float3 gradient = float3(-dx, 1, -dz);
//#else
//#if FRAGMENT_NORMALS
  float4 noise = sampleInf(in.cubeOrigin, in.cubeSize, in.cubeInner, uniforms.amplitudeLod, o, 0);
  float3 deriv = noise.yzw;
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
  float3 world2Sun = normalize(uniforms.sunLod - in.worldPositionLod);
  float sunStrength = saturate(dot(n, world2Sun));

  // Make dark bits easier to see.
//  sunStrength = sunStrength * 0.9 + 0.1;
  
  float3 sunColour = float3(1.64,1.27,0.99);
  float3 lin = sunStrength;
  lin *= sunColour;
  
  float3 rock(0.21, 0.2, 0.2);
  float3 water(0.1, 0.1, 0.7);
  float3 material = in.worldPositionLod.y < uniforms.radiusLod ? water : rock;
  material *= lin;

//  float shininess = 0.1;
  float3 colour = material * sunStrength * sunColour;

//  float3 rWorld2Sun = reflect(world2Sun, n);
//  float spec = dot(eye2World, rWorld2Sun);
//  float specStrength = saturate(shininess * spec);
//  specStrength = pow(specStrength, 10.0);
//  colour += sunColour * specStrength;
  
//  colour = material * sunStrength;
  float3 eye2World = normalize(in.worldPositionLod - uniforms.eyeLod);
  float3 sun2World = normalize(in.worldPositionLod - uniforms.sunLod);
  colour = applyFog(colour, dist * 120, eye2World, sun2World);
  colour = pow(colour, float3(1.0/2.2));

//  colour = n / 2.0 + 0.5;
  float tc = saturate(log((float)in.tier) / 10.0);
//  colour = float3(tc, tc, 1-tc);
  
  return float4(colour, 1.0);
}
