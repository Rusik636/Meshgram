// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_top;
uniform sampler2D u_input;
out vec4 frag_color;

vec4 sampleAt(vec2 uv) {
  return texture(u_input, clamp(uv, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
  float distanceFromEdge = mix(1.0 - uv.y, uv.y, u_top);
  float strength = 1.0 - smoothstep(0.16, 0.92, distanceFromEdge);
  vec2 stepSize = 1.65 * strength / u_size;
  vec4 softened = vec4(0.0);
  for (int y = -2; y <= 2; ++y) {
    float wy = y == 0 ? 0.375 : (y == -1 || y == 1 ? 0.25 : 0.0625);
    for (int x = -2; x <= 2; ++x) {
      float wx = x == 0 ? 0.375 : (x == -1 || x == 1 ? 0.25 : 0.0625);
      softened += sampleAt(uv + vec2(float(x), float(y)) * stepSize) * wx * wy;
    }
  }
  frag_color = mix(sampleAt(uv), softened, strength);
}
