-- loadShape reads OBJ models, with their material colors
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
