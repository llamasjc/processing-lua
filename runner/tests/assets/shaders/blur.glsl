uniform sampler2D texture;
uniform vec2 texOffset;
varying vec4 vertTexCoord;
uniform int radius;
void main() {
  vec4 sum = vec4(0.0);
  float n = 0.0;
  for (int i = -radius; i <= radius; i++) {
    for (int j = -radius; j <= radius; j++) {
      sum += texture2D(texture, vertTexCoord.st + vec2(i, j) * texOffset);
      n += 1.0;
    }
  }
  gl_FragColor = sum / n;
}
