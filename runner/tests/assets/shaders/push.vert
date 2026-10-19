// moves every corner right by `push` and passes how far across it is
uniform mat4 transform;
uniform float push;
attribute vec4 position;
attribute vec4 color;
varying vec4 vertColor;
varying float across;
void main() {
  gl_Position = transform * (position + vec4(push, 0.0, 0.0, 0.0));
  vertColor = color;
  across = (position.x + push) / 160.0;
}
