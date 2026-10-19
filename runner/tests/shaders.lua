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
  -- shader() colors the shapes drawn after it; vertColor is their fill
  local stripes = createShader([[
    varying vec4 vertColor;
    void main() {
      float on = mod(floor(gl_FragCoord.x / 10.0), 2.0);
      gl_FragColor = vec4(vertColor.rgb * on, 1.0);
    }
  ]])
  background(0, 0, 100) fill(0, 255, 0)
  shader(stripes) rect(40, 40, 80, 40)
  r, g, b = get(45, 60) assert(g == 0 and b == 0, "shader(): stripe off: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(55, 60) assert(g == 255 and b == 0, "shader(): stripe on, the fill's color: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(20, 20) assert(b == 100, "shader(): outside the shape untouched")
  -- each shape keeps its own fill; ellipses and shapes from vertices too
  fill(255, 0, 0) ellipse(30, 100, 30, 30)
  fill(255, 255, 255) beginShape() vertex(130, 90) vertex(158, 90) vertex(144, 118) endShape(CLOSE)
  resetShader()
  r, g, b = get(35, 100) assert(r == 255 and g == 0, "shader(): ellipse in its own fill: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(135, 92) assert(r == 255 and g == 255 and b == 255, "shader(): shape from vertices: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(55, 60) assert(g == 255 and r == 0, "an earlier shape keeps its fill: " .. r .. "," .. g .. "," .. b)
  -- a 3D shape, on both renderers
  background(0, 0, 100) fill(255, 255, 0)
  shader(stripes) push() translate(80, 60) box(60) pop() resetShader()
  local onx = (math.floor(80 / 10) % 2 == 1) and 80 or 90
  local offx = onx - 10
  r, g, b = get(onx + 2, 60) assert(r > 200 and g > 200 and b < 30, "shader() on a box, stripe on: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(offx + 2, 60) assert(r < 30 and g < 30 and b < 30, "shader() on a box, stripe off: " .. r .. "," .. g .. "," .. b)
  r, g, b = get(5, 5) assert(b == 100, "outside the box untouched")
  fill(0, 255, 0) rect(130, 40, 20, 20) r, g, b = get(140, 50) assert(g == 255, "resetShader: plain fill again")
  -- arrays: a uniform array set from a table, a const array, a local one
  local kernel = loadShader(dir .. "kernel.glsl") assert(kernel, "kernel loaded")
  background(0) fill(255) noStroke() rect(70, 50, 20, 20)
  local box = {} for i = 1, 9 do box[i] = 1 / 9 end
  kernel:set("kernel", box) filter(kernel)
  r = get(80, 60) assert(r > 250, "box blur keeps the middle: " .. r)
  r = get(70, 60) assert(near(r, 170), "box blur on the edge is 6/9: " .. r)
  r = get(69, 49) assert(near(r, 28), "box blur at the corner is 1/9: " .. r)
  -- an edge kernel: only the edges stay
  background(0) fill(255) rect(70, 50, 20, 20)
  kernel:set("kernel", {0, -1, 0, -1, 4, -1, 0, -1, 0}) filter(kernel)
  r = get(80, 60) assert(r == 0, "edge kernel: flat middle is dark")
  r = get(70, 60) assert(r > 250, "edge kernel: the edge is bright: " .. r)
  assert(createShader("uniform float a[3]; void main() { gl_FragColor = vec4(a); }") == nil, "a whole array as a value says so")
  -- a mistake says where and gives nothing back
  assert(createShader("void main() { gl_FragColor = vec4(oops); }") == nil, "a broken shader")
  -- plain filters still work
  background(255) filter(INVERT) assert(get(5, 5) == 0)
  print("ok") exit()
end
