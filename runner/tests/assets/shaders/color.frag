varying vec4 vertColor;
flat varying int side;
uniform bool showSide;
void main() {
  gl_FragColor = showSide ? (side == 0 ? vec4(1.0, 1.0, 0.0, 1.0) : vec4(0.0, 1.0, 1.0, 1.0)) : vertColor;
}
