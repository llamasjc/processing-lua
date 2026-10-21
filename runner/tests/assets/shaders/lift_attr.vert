// moves each corner up by its own "lift" attribute
uniform mat4 transform;
attribute vec4 position;
attribute vec4 color;
attribute float lift;
varying vec4 vertColor;
void main() {
  gl_Position = transform * (position - vec4(0.0, lift, 0.0, 0.0));
  vertColor = color;
}
