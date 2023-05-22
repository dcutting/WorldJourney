#include <metal_stdlib>
#include "Common.h"
#include "../WorldJourney/Maths.h"
#include "../WorldJourney/WorldTerrain.h"

using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float3 worldPosition;
  float3 normal;
  vector_int3 cubeOrigin;
  int cubeSize;
  float3 cubeInner;
};

//struct ControlPoint {
//  float4 position [[attribute(0)]];
//};
//
//[[patch(quad, 4)]]
//vertex VertexOut terrainium_vertex(patch_control_point<ControlPoint> control_points [[stage_in]],
//                                   uint patchID [[patch_id]],
//                                   float2 patch_coord [[position_in_patch]],
//                                   constant Uniforms &uniforms [[buffer(1)]]
//                                   ) {
//  float patchu = patch_coord.x;
//  float patchv = patch_coord.y;
//  float2 top = mix(control_points[0].position.xy, control_points[1].position.xy, patchu);
//  float2 bottom = mix(control_points[3].position.xy, control_points[2].position.xy, patchu);
//  float2 vid = mix(top, bottom, patchv);
//
//  float4 v = float4(vid.x, 0, vid.y, 1.0);
vertex VertexOut terrainium_vertex(constant float2 *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   constant QuadUniforms *quadUniforms [[buffer(2)]],
                                   uint id [[vertex_id]],
                                   ushort iid [[instance_id]]
                                   ) {
  float2 vid = vertices[id];
  float4 v;
  switch (uniforms.side) {
    case 0:
    case 3:
      v = float4(vid.x, 0, vid.y, 1.0);
      break;
    case 1:
    case 4:
      v = float4(0, vid.x, vid.y, 1.0);
      break;
    case 2:
    case 5:
      v = float4(vid.x, vid.y, 0, 1.0);
      break;
  }
  float3 vidp = v.xyz;
  float4 wp = quadUniforms[iid].modelMatrix * v;
  float4 noise = sampleInf(quadUniforms[iid].cubeOrigin, quadUniforms[iid].cubeSize, vidp);
  float3 dv(0);
  float3 wp3 = wp.xyz;
  wp3 = wp3 / length(wp3) * (uniforms.radiusLod + (noise.x / uniforms.lod));
  wp = float4(wp3, 1);
  dv = noise.yzw;
  float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * wp;

  return {
    .position = p,
    .worldPosition = wp.xyz / wp.w,
    .normal = dv,
    .cubeOrigin = quadUniforms[iid].cubeOrigin,
    .cubeSize = quadUniforms[iid].cubeSize,
    .cubeInner = vidp
  };
}

fragment float4 terrainium_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
  int ampl = 1;  // TODO. what should this be?
  float4 noise = sampleInf(in.cubeOrigin, in.cubeSize, in.cubeInner);
  float3 gradient = float3(noise.yzw);
  float3 g = gradient / (uniforms.radiusLod + (ampl * noise.x / uniforms.lod));
  float3 n = sphericalise_flat_gradient(g, ampl, normalize(in.worldPosition));

  float3 light = normalize(uniforms.sunPosition - in.worldPosition);
  float sunStrength = saturate(dot(n, light));
  
  float3 sunColour = float3(1.64,1.27,0.99);
  float3 lin = sunStrength;
  lin *= sunColour;
  
  float3 rock(0.21, 0.2, 0.2);
  float3 material = rock;
  material *= lin;

  float shininess = 0.1;
  float3 colour = material;

  float3 eye2World = normalize(in.worldPosition - uniforms.eye);
  float3 world2Sun = normalize(uniforms.sunPosition - in.worldPosition);

  float3 rWorld2Sun = reflect(world2Sun, n);
  float spec = dot(eye2World, rWorld2Sun);
  float specStrength = saturate(shininess * spec);
  specStrength = pow(specStrength, 10.0);
  colour += sunColour * specStrength;
  
  colour = sunColour * sunStrength;
  colour = pow(colour, float3(1.0/2.2));

//  colour = n / 2.0 + 0.5;
//  colour = float3(1);
  
  return float4(colour, 1.0);
}
