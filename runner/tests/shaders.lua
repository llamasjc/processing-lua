-- loadShader / filter(shader): GLSL filter shaders, on either renderer
-- stdout: ok
local dir = os.getenv("LUAMODE_TESTS") .. "/assets/shaders/"
local function near(a, b) return math.abs(a - b) <= 6 end
function setup() size(160, 120) noLoop() end
function draw()
  noStroke()
  local inv = loadShader(dir .. "invert.glsl") assert(inv, "loaded")
  background(255, 0, 0) fill(0, 0, 255) rect(0, 0, 80, 120)
  filter(inv)
  local r, g, b = get(10, 10) assert(r == 255 and g == 255 and b == 0, "invert left: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(100, 10) assert(r == 0 and g == 255 and b == 255, "invert right")
  -- uniforms, gl_FragCoord (from the bottom), bools
  local grad = loadShader(dir .. "grad.glsl")
  grad:set("amount", 1.0) grad:set("flip", true)
  filter(grad)
  r, g = get(0, 0) assert(r < 6 and g < 6, "gradient top left: " .. r .. "," .. g)
  r, g = get(159, 119) assert(r > 249 and g > 249, "gradient bottom right: " .. r .. "," .. g)
  r, g = get(80, 60) assert(near(r, 128) and near(g, 128), "gradient middle: " .. r .. "," .. g)
  -- loops, texOffset, int uniforms
  local blur = loadShader(dir .. "blur.glsl")
  background(0) fill(255) rect(70, 50, 20, 20)
  blur:set("radius", 2)
  filter(blur)
  r = get(80, 60) assert(r > 250, "blur keeps the middle")
  r = get(70, 60) assert(r > 100 and r < 200, "blur softens the edge: " .. r)
  r = get(10, 10) assert(r == 0, "blur leaves far pixels")
  -- functions with out parameters, mat2, mod, swizzle assignment, const
  local misc = loadShader(dir .. "misc.glsl")
  misc:set("time", 0)
  background(0) filter(misc)
  r, g, b = get(5, 5) assert(near(r, 26) and near(g, 26), "outside the circle: " .. r .. "," .. g)
  -- a shader written in the sketch
  local tint = createShader([[
    uniform sampler2D texture; varying vec4 vertTexCoord; uniform vec3 k;
    void main() { gl_FragColor = texture2D(texture, vertTexCoord.st) * vec4(k, 1.0); }
  ]])
  background(200) tint:set("k", 0.5, 1.0, 0.0) filter(tint)
  r, g, b = get(5, 5) assert(near(r, 100) and near(g, 200) and b == 0, "createShader + set(x, y, z): " .. r .. "," .. g .. "," .. b)
  -- a second image as a uniform
  local img = createImage(4, 4)
  for y = 0, 3 do for x = 0, 3 do imageSet(img, x, y, color(0, 0, 255)) end end
  local mixer = loadShader(dir .. "mixer.glsl")
  background(255, 0, 0) mixer:set("other", img) mixer:set("amount", 0.5) filter(mixer)
  r, g, b = get(80, 60) assert(near(r, 128) and g == 0 and near(b, 128), "second image: " .. r .. "," .. g .. "," .. b)
  -- a mistake says where and gives nothing back
  assert(createShader("void main() { gl_FragColor = vec4(oops); }") == nil, "a broken shader")
  -- plain filters still work
  background(255) filter(INVERT) assert(get(5, 5) == 0)
  print("ok") exit()
end
