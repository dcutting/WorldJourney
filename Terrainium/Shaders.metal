#include <metal_stdlib>
#include "Common.h"
#include "../WorldJourney/Maths.h"
#include "../WorldJourney/WorldTerrain.h"

using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float3 unitPositionLod;
  float3 worldPositionLod;
  float3 normal;
  vector_int3 cubeOrigin;
  int cubeSize;
  float3 cubeInner;
};

struct ControlPoint {
  float4 position [[attribute(0)]];
};

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
  float3 cubeInner = v.xyz;
  float4 noise = sampleInf(quadUniforms[iid].cubeOrigin, quadUniforms[iid].cubeSize, cubeInner);
  float4 wp = quadUniforms[iid].modelMatrix * v;
//  float3 wp3 = normalize(wp.xyz);
  float3 wp3 = wp.xyz;
  float3 displaced = wp3 * (uniforms.radiusLod);// + (uniforms.amplitudeLod * noise.x));
  displaced.y = uniforms.radiusLod + uniforms.amplitudeLod * noise.x;
  float4 p = uniforms.projectionMatrix * uniforms.viewMatrix * float4(displaced, 1);

  return {
    .position = p,
    .unitPositionLod = wp3,
    .worldPositionLod = displaced,
    .normal = noise.yzw,
    .cubeOrigin = quadUniforms[iid].cubeOrigin,
    .cubeSize = quadUniforms[iid].cubeSize,
    .cubeInner = cubeInner
  };
}

fragment float4 terrainium_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
  float4 noise = sampleInf(in.cubeOrigin, in.cubeSize, in.cubeInner);
  float3 gradient = float3(noise.yzw);
  float3 n = normalize(float3(-gradient.x, 1, -gradient.z));
//  float ampl = uniforms.amplitudeLod;
//  float3 g = gradient / (uniforms.radiusLod + (ampl * noise.x));
//  float3 n = sphericalise_flat_gradient(g, ampl, normalize(in.unitPositionLod));

//  float3 eye2World = normalize(in.worldPositionLod - uniforms.eyeLod);
  float3 world2Sun = normalize(uniforms.sunLod - in.worldPositionLod);
  float sunStrength = saturate(dot(n, world2Sun));
  
//  float3 sunColour = float3(1.64,1.27,0.99);
//  float3 lin = sunStrength;
//  lin *= sunColour;
  
  float3 rock(0.21, 0.2, 0.2);
  float3 material = rock;
//  material *= lin;

//  float shininess = 0.1;
  float3 colour = material * sunStrength;

//  float3 rWorld2Sun = reflect(world2Sun, n);
//  float spec = dot(eye2World, rWorld2Sun);
//  float specStrength = saturate(shininess * spec);
//  specStrength = pow(specStrength, 10.0);
//  colour += sunColour * specStrength;
  
//  colour = material * sunStrength;
  colour = pow(colour, float3(1.0/2.2));

//  colour = n / 2.0 + 0.5;
//  colour = float3(1);
  
  return float4(colour, 1.0);
}
