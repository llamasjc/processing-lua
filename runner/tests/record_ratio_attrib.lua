-- beginRecord / endRecord (SVG and PDF), windowRatio, attrib, loadBytes /
-- saveBytes, float / byte / char
-- stdout: ok
function setup() size(200, 100) noLoop() end
local function read(p) local f = io.open(p, "rb") local s = f:read("a") f:close() return s end
function draw()
  -- SVG: shapes after the transform, with their colors
  beginRecord(SVG, "out.svg")
  background(255) fill(255, 0, 0) stroke(0) strokeWeight(2)
  translate(10, 10) rect(0, 0, 50, 30) ellipse(100, 40, 20, 20)
  noFill() beginShape() vertex(0, 60) bezierVertex(20, 40, 40, 80, 60, 60) endShape()
  fill(0) text("hi <there>", 120, 80)
  assert(endRecord(), "svg written")
  resetMatrix()
  local svg = read("out.svg")
  assert(svg:find("<svg") and svg:find("M10.00 10.00 L60.00 10.00 L60.00 40.00 L10.00 40.00 Z", 1, true), "svg rect: " .. svg:sub(1, 400))
  assert(svg:find('fill="#ff0000"', 1, true) and svg:find('stroke-width="2.00"', 1, true), "svg colors")
  assert(svg:find("hi &lt;there&gt;", 1, true), "svg text")
  -- PDF: a real file with the shape in it
  beginRecord("out.pdf") background(255) fill(0, 0, 255) noStroke() rect(0, 0, 20, 20) endRecord()
  local pdf = read("out.pdf")
  assert(pdf:sub(1, 8) == "%PDF-1.4" and pdf:find("%%EOF", 1, true) and pdf:find("0.000 0.000 1.000 rg", 1, true), "pdf")
  assert(pdf:find("0.00 100.00 m", 1, true), "pdf flips y: " .. pdf)
  -- windowRatio: draw in 100x50 units, scaled 2x to the 200x100 canvas
  background(0) windowRatio(100, 50) noStroke() fill(0, 255, 0) rect(50, 0, 50, 50)
  assert(rwidth == 100 and rheight == 50, "rwidth / rheight")
  local _, g = get(150, 50) assert(g == 255, "scaled right half: " .. g)
  _, g = get(50, 50) assert(g == 0, "left half empty: " .. g)
  windowRatio(0, 0) resetMatrix()
  -- attrib: a value per vertex for a vertex shader
  do
    local dir = os.getenv("LUAMODE_TESTS") .. "/assets/shaders/"
    local s = loadShader(dir .. "plain.frag", dir .. "lift_attr.vert") assert(s, "lift_attr loaded")
    background(0) fill(255, 0, 0) shader(s)
    beginShape()
    attrib("lift", 40) vertex(20, 80) vertex(60, 80)
    attrib("lift", 0) vertex(60, 90) vertex(20, 90)
    endShape(CLOSE)
    resetShader()
    local r = get(40, 45) assert(r == 255, "top corners lifted by their attrib: " .. r)
  end
  -- bytes
  assert(saveBytes("b.bin", { 1, 255, 256, -1 }), "saveBytes")
  local b = loadBytes("b.bin") assert(#b == 4 and b[2] == 255 and b[3] == 0 and b[4] == 255, "loadBytes")
  assert(float("3.5") == 3.5 and byte(200) == -56 and char(65) == "A", "conversions")
  print("ok") exit()
end
