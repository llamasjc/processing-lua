-- A box and a sphere, lit, turning in 3D. Move the mouse to turn the light.

local a = 0

function setup()
  size(640, 400, P3D)
end

function draw()
  background(24)
  ambientLight(60, 60, 70)
  local lx = (mouseX / width - 0.5) * 2
  local ly = (mouseY / height - 0.5) * 2
  directionalLight(220, 210, 200, -lx, -ly, -1)

  pushMatrix()
  translate(220, 200, 0)
  rotateX(a * 0.7)
  rotateY(a)
  fill(220, 90, 60)
  stroke(255, 255, 255, 120)
  box(140)
  popMatrix()

  pushMatrix()
  translate(470, 200, -60)
  noStroke()
  fill(70, 150, 255)
  sphere(110)
  popMatrix()

  a = a + 0.01
end
