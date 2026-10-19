uniform sampler2D texture;
uniform sampler2D other;
uniform float amount;
varying vec4 vertTexCoord;
void main() {
  vec4 a = texture2D(texture, vertTexCoord.st);
  vec4 b = texture2D(other, vertTexCoord.st);
  gl_FragColor = mix(a, b, amount);
}
