-- loadShape reads OBJ models, with their material colors
-- stdout: ok
local function px(x, y) local r, g, b = get(x, y) return r .. "," .. g .. "," .. b end
function setup() size(200, 200) noLoop() end
function draw()
  local s = loadShape(os.getenv("LUAMODE_TESTS") .. "/assets/cube.obj")
  assert(s and s.width == 2, "loaded")
  background(0) translate(100, 100) scale(40)
  shape(s, 0, 0)
  local r, g, b = get(100, 100)
  assert(r > 200 and g < 20, "front face is the red material: " .. px(100, 100))
  s:disableStyle() fill(0, 0, 255) background(0) shape(s, 0, 0)
  assert(px(100, 100) == "0,0,255", "disableStyle")
  print("ok") exit()
end
