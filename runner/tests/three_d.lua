-- stdout: center 40 30 front true hidden true
function setup()
  size(80, 60, P3D)
  background(0)
  noStroke()
  -- a red box behind a green one: the green one wins where they overlap
  fill(0, 255, 0)
  pushMatrix() translate(40, 30, 10) box(6) popMatrix()
  fill(255, 0, 0)
  pushMatrix() translate(40, 30, -20) box(30) popMatrix()
  local r, g = get(40, 30)
  local r2 = get(40, 20)
  local sx, sy = math.floor(screenX(40, 30, 0) + 0.5), math.floor(screenY(40, 30, 0) + 0.5)
  lights() sphereDetail(8) sphere(5) noLights()
  rotateX(0.3) rotateY(0.2) rotateZ(0.1)
  stroke(255) line(0, 0, 0, 10, 10, -10) point(5, 5, 5)
  print(string.format("center %d %d front %s hidden %s", sx, sy, tostring(g > 200 and r < 50), tostring(r2 > 200)))
  exit()
end
