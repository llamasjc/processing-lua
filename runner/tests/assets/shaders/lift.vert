// lifts every corner by the red of the middle of `height`, times 40
uniform mat4 transform;
uniform sampler2D height;
attribute vec4 position;
attribute vec4 color;
varying vec4 vertColor;
void main() {
  float up = texture2D(height, vec2(0.5, 0.5)).r * 40.0;
  gl_Position = transform * (position - vec4(0.0, up, 0.0, 0.0));
  vertColor = color;
}
