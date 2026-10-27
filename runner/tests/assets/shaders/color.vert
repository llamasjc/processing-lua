// passes each vertex's own fill, and an int that says which half it's on
uniform mat4 transform;
attribute vec4 position;
attribute vec4 color;
varying vec4 vertColor;
flat varying int side;
void main() {
  gl_Position = transform * position;
  vertColor = color;
  side = position.x < 100.0 ? 0 : 1;
}
