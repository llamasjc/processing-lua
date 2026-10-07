-- stdout: ok
local function near(a, b) return math.abs(a - b) <= 2 end
function setup() size(50, 50) noLoop() end
function draw()
  background(255, 128, 0)      local r, g, b = get(1, 1)  assert(r == 255 and near(g, 128) and b == 0)
  background(77)               r, g, b = get(1, 1)        assert(near(r, 77) and near(g, 77) and near(b, 77))
  background(300, -20, 1e9)    r, g, b = get(1, 1)        assert(r == 255 and g == 0 and b == 255, "clamped")
  colorMode(HSB, 360, 100, 100)
  background(0, 100, 100)      r, g, b = get(1, 1)        assert(r == 255 and g == 0 and b == 0, "HSB red")
  background(120, 100, 100)    r, g, b = get(1, 1)        assert(r == 0 and g == 255 and b == 0, "HSB green")
  colorMode(RGB, 1)
  background(0, 0, 1)          r, g, b = get(1, 1)        assert(b == 255 and r == 0, "RGB 0..1")
  colorMode(RGB, 255) colorMode(RGB, 0) colorMode(HSB, -1, 0, 0/0) colorMode() colorMode(RGB, 255)
  noStroke() fill(0, 255, 0, 255) rect(0, 0, 50, 50)
  r, g, b = get(25, 25) assert(g == 255 and r == 0)
  fill(255, 0, 0, 0) rect(0, 0, 50, 50)          -- fully transparent: nothing changes
  r, g, b = get(25, 25) assert(g == 255 and r == 0, "alpha 0 draws nothing")
  fill() stroke() background() tint() noTint()   -- no arguments at all is survivable
  local lr, lg, lb = lerpColor(0, 0, 0, 100, 200, 50, 0.5)
  assert(lr == 50 and lg == 100 and lb == 25)
  r, g, b = get(-1, -1) assert(r == 0)  r = get(1e9, 5) assert(r == 0)
  print("ok") exit()
end
