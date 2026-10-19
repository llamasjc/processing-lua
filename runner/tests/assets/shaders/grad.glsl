uniform vec2 resolution;
uniform float amount;
uniform bool flip;
void main() {
  vec2 p = gl_FragCoord.xy / resolution;
  float v = flip ? 1.0 - p.y : p.y;
  gl_FragColor = vec4(p.x * amount, v, 0, 1);
}
