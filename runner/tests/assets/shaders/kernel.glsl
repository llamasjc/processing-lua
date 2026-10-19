uniform sampler2D texture;
uniform vec2 texOffset;
uniform float kernel[9];
varying vec4 vertTexCoord;
const vec2 offsets[9] = vec2[9](vec2(-1, -1), vec2(0, -1), vec2(1, -1),
                                vec2(-1, 0), vec2(0, 0), vec2(1, 0),
                                vec2(-1, 1), vec2(0, 1), vec2(1, 1));
void main() {
  float seen[3];
  vec4 sum = vec4(0.0);
  for (int i = 0; i < 9; i++) {
    sum += texture2D(texture, vertTexCoord.st + offsets[i] * texOffset) * kernel[i];
  }
  seen[0] = sum.r; seen[1] = sum.g; seen[2] = sum.b;
  float total = 0.0;
  for (int i = 0; i < 3; i++) total += seen[i];
  gl_FragColor = vec4(sum.rgb, total > -1.0 ? 1.0 : 0.0);
}
