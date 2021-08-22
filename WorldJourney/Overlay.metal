#include <metal_stdlib>
#include "Common.h"

using namespace metal;

struct OverlayOut {
  float4 position [[position]];
  float2 uv;
};



/** overlay vertex shader */

vertex OverlayOut overlay_vertex(constant float2 *vertices [[buffer(0)]],
                                         constant float2 *uv [[buffer(1)]],
                                         uint id [[vertex_id]]) {
  return {
    .position = float4(vertices[id], 0.0, 1.0),
    .uv = uv[id]
  };
}



/** overlay fragment shader */

fragment float4 overlay_fragment(OverlayOut in [[stage_in]],
                                 texture2d<float> worldTexture [[texture(0)]],
                                 texture2d<float> overlayTexture [[texture(1)]]) {
  constexpr sampler sample(min_filter::linear, mag_filter::linear);
  float4 world = worldTexture.sample(sample, in.uv);
  float4 overlay = overlayTexture.sample(sample, in.uv);
  return mix(world, overlay, overlay.a);
}
