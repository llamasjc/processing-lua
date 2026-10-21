-- loadShader(frag, vert): a vertex shader places the corners and passes
-- values along to the fragment shader
-- stdout: ok
local dir = os.getenv("LUAMODE_TESTS") .. "/assets/shaders/"
local function near(a, b, k) return math.abs(a - b) <= (k or 8) end
function setup() size(160, 120) noLoop() end
function draw()
  noStroke()
  local s = loadShader(dir .. "push.frag", dir .. "push.vert") assert(s, "loaded")
  -- the vertex shader moves the rect 40 to the right
  background(0) fill(0, 255, 0)
  s:set("push", 40) s:set("ramp", false)
  shader(s) rect(20, 40, 40, 40)
  local r, g, b = get(30, 60) assert(g == 0, "moved away from where it was drawn: " .. g)
  r, g, b = get(80, 60) assert(g == 255 and r == 0, "moved to its new place: " .. r .. "," .. g .. "," .. b)
  -- a varying of its own, blended across the shape
  background(0) s:set("push", 0) s:set("ramp", true)
  rect(0, 0, 160, 120)
  r = get(80, 60) assert(near(r, 128), "varying halfway across: " .. r)
  r = get(8, 60) assert(r < 20, "varying at the left: " .. r)
  r = get(152, 60) assert(r > 235, "varying at the right: " .. r)
  -- with a camera and a box, still drawn
  background(0) s:set("ramp", false) fill(255)
  translate(80, 60, 0) rotateY(0.5) box(40)
  r = get(80, 60) assert(r == 255, "box through the vertex shader: " .. r)
  resetShader()
  -- a vertex shader reading an image (a height map)
  resetMatrix()
  local lift = loadShader(dir .. "plain.frag", dir .. "lift.vert") assert(lift, "lift loaded")
  local white = createImage(1, 1) imageSet(white, 0, 0, color(255))
  lift:set("height", white)
  background(0) fill(255, 0, 0) shader(lift) rect(60, 60, 40, 40)
  r = get(80, 40) assert(r == 255, "lifted by the image: " .. r)
  r = get(80, 90) assert(r == 0, "no longer where it was drawn: " .. r)
  resetShader()
  print("ok")
  exit()
end
