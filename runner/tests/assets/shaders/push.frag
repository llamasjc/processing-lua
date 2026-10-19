varying vec4 vertColor;
varying float across;
uniform bool ramp;
void main() {
  gl_FragColor = ramp ? vec4(across, 0.0, 0.0, 1.0) : vertColor;
}
