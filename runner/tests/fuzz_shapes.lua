-- stdout: ok
-- timeout: 60
-- Every drawing call with sizes and positions nobody would type on purpose.
-- Nothing may hang, crash or take seconds.
local inf, nan = math.huge, 0/0
local nasty = { 0, -1, 1, 0.5, -0.5, 50, 1e3, -1e3, 1e6, -1e6, 1e12, -1e12, 1e30, inf, -inf, nan }
local function pick(i) return nasty[(i % #nasty) + 1] end

function setup() size(120, 90) end
function draw()
  background(0)
  local k = frameCount * 7
  for i = 0, 40 do
    local a, b, c, d = pick(k + i), pick(k + i * 3 + 1), pick(k + i * 5 + 2), pick(k + i * 7 + 3)
    local e, f, g, h = pick(k + i * 11), pick(k + i * 13), pick(k + i * 17), pick(k + i * 19)
    stroke(255) strokeWeight(pick(i)) fill(pick(i), 100, 100, pick(i + 1))
    rect(a, b, c, d) rect(a, b, c, d, e) square(a, b, c)
    ellipse(a, b, c, d) circle(a, b, c)
    line(a, b, c, d) point(a, b)
    triangle(a, b, c, d, e, f) quad(a, b, c, d, e, f, g, h)
    arc(a, b, c, d, e, f) arc(50, 50, 30, 30, e, f)
    bezier(a, b, c, d, e, f, g, h) curve(a, b, c, d, e, f, g, h)
    for _, kind in ipairs({ POINTS, LINES, TRIANGLES, TRIANGLE_STRIP, TRIANGLE_FAN, QUADS, QUAD_STRIP, POLYGON, 999, -1 }) do
      beginShape(kind)
      vertex(a, b) vertex(c, d) vertex(e, f) vertex(g, h)
      bezierVertex(a, b, c, d, e, f) quadraticVertex(a, b, c, d) curveVertex(a, b) curveVertex(c, d)
      endShape(CLOSE)
    end
    beginShape() endShape()
    endShape() endShape()                       -- end without begin
    beginShape() vertex(1, 1)                   -- begin without end, then begin again
    beginShape() vertex(2, 2) endShape()
    pushMatrix()
    translate(a, b) rotate(c) scale(d) scale(e, f)
    rect(10, 10, 20, 20) ellipse(10, 10, 20, 20) text("fuzz", 10, 10)
    popMatrix()
    scale(0) rect(1, 1, 5, 5) ellipse(1, 1, 5, 5) line(0, 0, 9, 9) resetMatrix()
    textSize(pick(i)) text("t", a, b) textSize(12)
    noFill() rect(5, 5, 20, 20) noStroke() ellipse(30, 30, 10, 10)
    strokeCap(i - 20) strokeJoin(i * 1000) rectMode(i - 5) ellipseMode(-i)
    rectMode(CORNER) ellipseMode(CENTER) strokeWeight(1)
    noise(a) noise(a, b) noise(a, b, c) noise() random(a) random(a, b) noiseDetail(4, 0.5) noiseDetail(-3)
  end
  popMatrix() popMatrix() popStyle() popStyle()  -- more pops than pushes
  for _ = 1, 500 do pushMatrix() pushStyle() end -- and far more pushes than pops
  if frameCount == 16 then print("ok") exit() end
end
