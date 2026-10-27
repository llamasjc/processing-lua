-- a vertex shader's color is each vertex's own fill; int varyings come from one corner
-- stdout: ok
local dir = os.getenv("LUAMODE_TESTS") .. "/assets/shaders/"
local function near(a, b) return math.abs(a - b) <= 40 end
function setup() size(200, 100) noLoop() end
function draw()
  noStroke() background(0)
  local s = loadShader(dir .. "color.frag", dir .. "color.vert") assert(s, "loaded")
  s:set("showSide", false)
  shader(s)
  beginShape()
  fill(255, 0, 0) vertex(0, 0)
  fill(0, 0, 255) vertex(200, 0)
  fill(0, 0, 255) vertex(200, 100)
  fill(255, 0, 0) vertex(0, 100)
  endShape(CLOSE)
  local r, g, b = get(5, 50) assert(r > 200 and b < 60, "left corner red: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(195, 50) assert(b > 200 and r < 60, "right corner blue: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(100, 50) assert(near(r, 128) and near(b, 128), "blended in the middle: " .. r .. "," .. g .. "," .. b)
  -- a box drawn through the vertex shader takes the fill
  background(0) fill(0, 255, 0) translate(100, 50, 0) rotateY(0.4) box(40) resetMatrix()
  r, g, b = get(100, 50) assert(g > 200 and r < 60, "box through the vertex shader: " .. r .. "," .. g .. "," .. b)
  -- int varying: one value per triangle, not blended
  background(0) s:set("showSide", true)
  rect(0, 0, 90, 100)
  r, g, b = get(45, 50) assert(r > 200 and g > 200 and b < 60, "int varying, left: " .. r .. "," .. g .. "," .. b)
  rect(110, 0, 90, 100)
  r, g, b = get(155, 50) assert(g > 200 and b > 200 and r < 60, "int varying, right: " .. r .. "," .. g .. "," .. b)
  resetShader()
  print("ok") exit()
end
