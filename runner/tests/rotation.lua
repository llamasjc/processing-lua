-- images, layers and text follow rotate() and shear
-- stdout: ok
local function ink(x0, y0, x1, y1)
  local n = 0
  for y = y0, y1 do for x = x0, x1 do local r, g, b = get(x, y) if r + g + b > 0 then n = n + 1 end end end
  return n
end
function setup() size(200, 200) noLoop() end
function draw()
  local img = loadImage(os.getenv("LUAMODE_TESTS") .. "/assets/halves.jpg")   -- left red, right blue, 32x24
  -- upright, own size: exact copy
  noSmooth() background(0) image(img, 10, 10)
  local r, g, b = get(12, 20) assert(r > 200 and b < 70, "upright: left is red")
  r, g, b = get(40, 20) assert(b > 200, "upright: right is blue") assert(ink(43, 0, 199, 199) == 0 and ink(0, 35, 199, 199) == 0, "upright: nothing outside")
  -- a quarter turn: red ends up on top, blue below
  background(0) push() translate(100, 100) rotate(HALF_PI) image(img, -16, -12) pop()
  r, g, b = get(100, 90) assert(r > 200 and b < 70, "turned: red on top " .. r .. "," .. b)
  r, g, b = get(100, 110) assert(b > 200 and r < 70, "turned: blue below")
  assert(ink(0, 0, 80, 199) == 0 and ink(120, 0, 199, 199) == 0, "turned: 24 wide now")
  assert(ink(88, 84, 111, 115) == 24 * 32, "turned: every pixel of it, " .. ink(88, 84, 111, 115))
  -- half a turn flips it
  background(0) push() translate(100, 100) rotate(PI) image(img, -16, -12) pop()
  r, g, b = get(90, 100) assert(b > 200, "half turn: blue on the left") r, g, b = get(110, 100) assert(r > 200, "half turn: red on the right")
  -- shear slants it; mirrored scale flips it
  background(0) push() translate(60, 60) shearX(0.5) image(img, 0, 0, 64, 48) pop()
  assert(ink(60, 60, 62, 62) > 0 and ink(60, 100, 75, 107) == 0 and ink(100, 100, 120, 107) > 0, "shear slants the picture")
  background(0) push() translate(100, 100) scale(-1, 1) image(img, 0, 0) pop()
  r, g, b = get(95, 110) assert(r > 200, "mirrored: red next to the axis") assert(ink(101, 0, 199, 199) == 0, "mirrored: all on the left")
  smooth()
  -- a layer turns too
  local pg = createGraphics(40, 10) pg:beginDraw() pg:background(255) pg:endDraw()
  background(0) push() translate(100, 100) rotate(HALF_PI) image(pg, 0, 0) pop()
  assert(ink(91, 101, 99, 138) > 300 and ink(101, 100, 199, 199) == 0, "layer turned a quarter")

  -- text: upright it runs right, turned a quarter it runs down
  for _, font in ipairs { 0, createFont("DejaVu Sans", 20) } do
    textFont(font) if font == 0 then textSize(16) end
    fill(255) background(0) text("IIIIIIII", 100, 100)
    assert(ink(100, 70, 199, 105) > 40 and ink(0, 110, 199, 199) == 0, "upright text runs right (font " .. font .. ")")
    background(0) push() translate(100, 100) rotate(HALF_PI) text("IIIIIIII", 0, 0) pop()
    assert(ink(95, 100, 135, 199) > 40 and ink(140, 0, 199, 199) == 0 and ink(0, 0, 199, 95) == 0, "turned text runs down (font " .. font .. ")")
  end
  -- nothing here may fail or hang
  push() scale(0, 1) image(img, 0, 0) text("x", 0, 0) pop() push() rotate(0/0) image(img, 0, 0) text("x", 0, 0) pop()
  push() scale(1e9) rotate(1) image(img, 0, 0) pop() push() rotate(1) image(img, 0, 0, 0, 0) image(img, 0, 0, -50, 1e9) pop()
  print("ok") exit()
end
