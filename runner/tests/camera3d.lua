-- beginCamera / endCamera, frustum, ortho with edges, model and screen coordinates
-- stdout: ok
-- libprocessing smooths textures and blends in linear light, so colors are
-- compared with a little room
local function px(x, y)
  local r, g, b = get(x, y)
  local function snap(v) for _, t in ipairs({0, 255}) do if math.abs(v - t) <= 12 then return t end end return v end
  return snap(r) .. "," .. snap(g) .. "," .. snap(b)
end
function setup() size(200, 200) noLoop() end
function draw()
  noStroke() noSmooth() fill(255)
  -- moving the camera right moves things left
  background(0)
  beginCamera() translate(50, 0, 0) endCamera()
  rect(90, 90, 20, 20)
  assert(px(50, 100) == "255,255,255" and px(100, 100) == "0,0,0", "camera moved: " .. px(50, 100))
  camera()
  -- ortho with the screen's own edges matches 2D
  ortho(-100, 100, -100, 100) background(0) rect(10, 10, 20, 20)
  assert(px(20, 20) == "255,255,255", "ortho(l, r, b, t)")
  perspective()
  -- frustum like the default perspective
  local ez = 100 / math.tan(math.pi / 6)
  local n = ez / 10
  local half = n * math.tan(math.pi / 6)
  frustum(-half, half, -half, half, n, ez * 10)
  background(0) rect(10, 10, 20, 20) assert(px(20, 20) == "255,255,255", "frustum")
  perspective()
  translate(10, 20, 30)
  assert(math.abs(modelX(1, 2, 3) - 11) < 1e-3 and math.abs(modelY(1, 2, 3) - 22) < 1e-3 and math.abs(modelZ(1, 2, 3) - 33) < 1e-3, "modelX/Y/Z")
  local z1, z2 = screenZ(0, 0, 0), screenZ(0, 0, -100)
  assert(z2 > z1, "screenZ grows away from the camera")
  rotate(HALF_PI, 0, 0, 1)
  assert(math.abs(modelX(10, 0, 0) - 10) < 1e-3 and math.abs(modelY(10, 0, 0) - 30) < 1e-3, "rotate around an axis")
  print("ok") exit()
end
