-- beginRecord keeps images, fonts and 3D: SVG and PDF
-- stdout: ok
function setup() size(200, 120, P3D) noLoop() end
local function read(p) local f = io.open(p, "rb") local s = f:read("a") f:close() return s end
local function count(s, pat) local n = 0 for _ in s:gmatch(pat) do n = n + 1 end return n end
function draw()
  local img = createImage(4, 4)
  for y = 0, 3 do for x = 0, 3 do imageSet(img, x, y, color(255, 0, 0)) end end
  local f = createFont("DejaVu Sans", 20)
  if f == 0 then f = createFont("sans-serif", 20) end

  beginRecord(SVG, "more.svg")
  background(255)
  image(img, 10, 10, 40, 40)
  if f ~= 0 then textFont(f) end
  fill(0) text("Font", 60, 40)
  lights() noStroke() fill(200, 100, 50)
  translate(150, 70, 0) rotateY(0.6) box(40)
  endRecord()
  resetMatrix() noLights()

  local svg = read("more.svg")
  assert(svg:find("data:image/png;base64,", 1, true), "svg has the image")
  if f ~= 0 then assert(svg:find("@font-face", 1, true) and svg:find('font-family="f0', 1, true), "svg has the font") end
  -- a box is 12 triangles (some may face away but all are kept)
  assert(count(svg, "<path ") >= 12, "svg has the box's triangles: " .. count(svg, "<path "))

  beginRecord("more.pdf")
  background(255) image(img, 10, 10, 40, 40)
  if f ~= 0 then textFont(f) end
  fill(0) text("Font", 60, 40)
  endRecord()
  local pdf = read("more.pdf")
  assert(pdf:find("/Im0 Do", 1, true) and pdf:find("/Subtype /Image", 1, true), "pdf has the image")
  if f ~= 0 then assert(pdf:find("/FontFile2", 1, true) and pdf:find("/F2 20 Tf", 1, true), "pdf has the font") end
  print("ok") exit()
end
