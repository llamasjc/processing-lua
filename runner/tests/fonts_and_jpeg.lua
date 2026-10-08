-- TrueType fonts and JPEG images
-- stdout: ok
-- stderr: no-such-font-file.ttf
local here = (os.getenv("LUAMODE_TESTS") or ".") .. "/"
local function ink(x0, y0, x1, y1)        -- how many pixels in the box are not black
  local n = 0
  for y = y0, y1 do for x = x0, x1 do local r, g, b = get(x, y) if r + g + b > 0 then n = n + 1 end end end
  return n
end
function setup() size(300, 120) noLoop() end
function draw()
  -- JPEG, by content: also when the file has the wrong extension
  for _, name in ipairs { "assets/halves.jpg", "assets/wrongname.png" } do
    local img = loadImage(here .. name)
    assert(img ~= 0, name .. " loads")
    assert(imageWidth(img) == 32 and imageHeight(img) == 24, "size")
    background(0) image(img, 0, 0)
    local r, g, b = get(4, 12) assert(r > 200 and b < 70, "left half is red: " .. r .. "," .. b)
    r, g, b = get(28, 12) assert(b > 200 and r < 70, "right half is blue")
  end

  -- fonts: any installed font will do
  local f = createFont("DejaVu Sans", 40)
  if f == 0 then f = createFont("sans-serif", 40) end
  assert(f ~= 0, "an installed font was found")
  background(0) fill(255)
  textSize(12) local narrow = textWidth("Wide World")       -- built-in font
  textFont(f)                                                -- brings its size, 40
  local w = textWidth("Wide World")
  assert(w > narrow * 1.5, "font has its own widths: " .. w)
  assert(textAscent() > 20 and textAscent() < 60 and textDescent() > 2, "font metrics")
  assert(textWidth("iii") < textWidth("WWW"), "letters have different widths")
  text("Wide World", 10, 60)
  assert(ink(10, 20, 10 + math.floor(w), 75) > 300, "text was drawn")
  assert(ink(0, 80, 299, 119) == 0, "nothing below the line")
  local r = get(0, 0) assert(r == 0)
  -- smooth letters: some pixels are in between
  local grey = 0
  for y = 20, 75 do for x = 10, 250 do local v = get(x, y) if v > 0 and v < 255 then grey = grey + 1 end end end
  assert(grey > 50, "letters have smooth edges")

  -- size, alignment, lines, leading
  background(0) textFont(f, 16) assert(textWidth("Wide World") < w * 0.6, "textFont(f, size)")
  textAlign(RIGHT) text("right", 290, 30) assert(ink(230, 10, 290, 35) > 20 and ink(291, 0, 299, 119) == 0, "RIGHT")
  textAlign(CENTER, CENTER) text("mid", 150, 60) assert(ink(120, 45, 180, 75) > 20, "CENTER")
  textAlign(LEFT, BASELINE)
  background(0) textLeading(40) text("a\nb", 10, 20) assert(ink(5, 45, 40, 65) > 5, "second line where textLeading put it")
  textLeading(0)
  -- follows translate and scale
  background(0) push() translate(100, 50) scale(2) text("X", 0, 0) pop() assert(ink(100, 20, 140, 52) > 30, "scaled and moved")
  -- odd input never breaks anything
  text("", 0, 0) text("\n\n", 0, 0) text("caf\xC3\xA9 \xE2\x98\x83 \xFF", 10, 100) text("x", 1e9, 0/0) textSize(0) textSize(1e9) text("big", 0, 0) textSize(16)

  -- back to the built-in font, and failures
  textFont(0) textSize(12) assert(textWidth("Wide World") == narrow, "textFont(0) is the built-in font")
  assert(createFont(here .. "no-such-font-file.ttf", 12) == 0, "missing font file")
  assert(createFont(here .. "assets/halves.jpg", 12) == 0, "not a font")
  textFont(12345) text("still fine", 10, 20) textFont(-1)
  assert(loadFont("DejaVu Sans") ~= 0 or true)
  print("ok") exit()
end
