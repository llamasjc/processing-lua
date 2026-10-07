-- colors, vectors, pixels, modes, strings, time: the API added after the first release
-- stdout: ok
local function near(a, b, what) assert(math.abs(a - b) < 0.01, what .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
function setup() size(80, 80) noLoop() end
function draw()
  -- color values
  local c = color(255, 128, 0)
  assert(math.type(c) == "integer", "color() is one integer")
  assert(red(c) == 255 and green(c) == 128 and blue(c) == 0 and alpha(c) == 255, "channels")
  assert(alpha(color(10, 20, 30, 40)) == 40)
  assert(red(200) == 200, "a plain gray is still a gray")
  background(c)
  local r, g, b = get(5, 5)
  assert(r == 255 and g == 128 and b == 0, "background(color)")
  fill(color(0, 0, 255)) noStroke() rect(0, 0, 40, 40)
  r, g, b = get(10, 10) assert(b == 255 and r == 0, "fill(color)")
  background(255) r = get(1, 1) assert(r == 255, "background(255) is white, not a packed color")
  local mid = lerpColor(color(0, 0, 0), color(200, 100, 50), 0.5)
  assert(red(mid) == 100 and green(mid) == 50 and blue(mid) == 25, "lerpColor of two colors")
  local lr, lg, lb = lerpColor(0, 0, 0, 200, 100, 50, 0.5)
  assert(lr == 100 and lg == 50 and lb == 25, "lerpColor of six numbers")
  near(brightness(color(255, 0, 0)), 255, "brightness") near(saturation(color(255, 0, 0)), 255, "saturation")
  near(hue(color(0, 255, 0)), 85, "hue of green")
  colorMode(HSB, 360, 100, 100) near(hue(color(120, 100, 100)), 120, "hue in HSB 360") colorMode(RGB, 255)

  -- pixels
  background(0) set(3, 4, color(9, 8, 7)) r, g, b = get(3, 4) assert(r == 9 and g == 8 and b == 7, "set(color)")
  set(5, 5, 1, 2, 3) r, g, b = get(5, 5) assert(r == 1 and g == 2 and b == 3, "set(r, g, b)")
  set(-5, 1e9, 255) set(0/0, 0, 255)

  -- blend modes
  background(100) noStroke()
  blendMode(ADD) fill(50) rect(0, 0, 10, 10) r = get(5, 5) assert(r == 150, "ADD: " .. r)
  blendMode(SUBTRACT) fill(30) rect(0, 0, 10, 10) r = get(5, 5) assert(r == 120, "SUBTRACT: " .. r)
  blendMode(MULTIPLY) fill(127.5) rect(20, 0, 10, 10) r = get(25, 5) assert(r == 50, "MULTIPLY: " .. r)
  blendMode(DARKEST) fill(40) rect(40, 0, 10, 10) r = get(45, 5) assert(r == 40, "DARKEST")
  blendMode(LIGHTEST) fill(40) rect(60, 0, 10, 10) r = get(65, 5) assert(r == 100, "LIGHTEST")
  blendMode(BLEND) fill(7) rect(0, 0, 10, 10) r = get(5, 5) assert(r == 7, "BLEND")
  blendMode(12345) blendMode(-1)

  -- caps, joins, arcs, shear: must draw something and never fail
  background(0) stroke(255) strokeWeight(10)
  strokeCap(SQUARE) line(20, 20, 60, 20) r = get(17, 20) assert(r == 0, "SQUARE stops at the end")
  strokeCap(PROJECT) line(20, 40, 60, 40) r = get(17, 40) assert(r == 255, "PROJECT goes past the end")
  strokeCap(ROUND) line(20, 60, 60, 60) r = get(17, 60) assert(r == 255, "ROUND goes past the end")
  r = get(15, 55) assert(r == 0, "ROUND has no square corner")
  for _, j in ipairs { MITER, BEVEL, ROUND, 99 } do strokeJoin(j) rect(20, 20, 30, 30) triangle(10, 70, 40, 10, 70, 70) end
  beginShape() vertex(5, 5) vertex(40, 70) vertex(75, 5) endShape() beginShape() vertex(5, 5) vertex(40, 70) vertex(75, 5) endShape(CLOSE)
  strokeWeight(1) background(0) fill(255) noStroke()
  arc(40, 40, 60, 60, 0, PI) r = get(40, 50) assert(r == 255, "arc fills") r = get(40, 30) assert(r == 0, "only the lower half")
  background(0) arc(40, 40, 60, 60, 0, HALF_PI, PIE) r = get(45, 45) assert(r == 255, "PIE reaches the centre")
  background(0) arc(40, 40, 60, 60, 0, HALF_PI, CHORD) r = get(45, 45) assert(r == 0, "CHORD does not reach the centre")
  r = get(58, 58) assert(r == 255, "CHORD fills beyond the chord")
  background(0) arc(40, 40, 60, 60, 0, HALF_PI, OPEN) stroke(255) arc(40, 40, 60, 60, 0, 7, 99)
  push() shearX(0.3) shearY(-0.2) applyMatrix(1, 0, 0, 1, 5, 5) rect(10, 10, 20, 20) pop() shearX(0/0)

  -- images
  background(0, 0, 255) saveFrame("shot.png") local img = loadImage("shot.png")
  assert(imageWidth(img) == 80 and imageHeight(img) == 80, "image size") assert(imageWidth(0) == 0)
  background(0) imageMode(CENTER) image(img, 40, 40, 20, 20)
  r, g, b = get(40, 40) assert(b == 255, "CENTER: middle") r, g, b = get(5, 5) assert(b == 0, "CENTER: corner untouched")
  imageMode(CORNERS) image(img, 0, 0, 10, 10) imageMode(CORNER) imageMode(77)

  -- vectors
  local v = createVector(3, 4) near(v:mag(), 5, "mag")
  local w = v:copy():add(createVector(1, 1)) assert(w.x == 4 and w.y == 5 and v.x == 3, "copy/add")
  v:add(1, 2) assert(v.x == 4 and v.y == 6, "add numbers") v:sub(createVector(4, 6)) assert(v.x == 0 and v.y == 0)
  local s = createVector(1, 2) + createVector(3, 4) assert(s.x == 4 and s.y == 6, "operator +")
  assert((createVector(2, 4) * 2).y == 8 and (2 * createVector(2, 4)).x == 4 and (createVector(2, 4) / 2).x == 1)
  near(createVector(10, 0):normalize():mag(), 1, "normalize") near(createVector(0, 0):normalize():mag(), 0, "normalize zero")
  near(createVector(10, 0):limit(3).x, 3, "limit") near(createVector(1, 0):rotate(HALF_PI).y, 1, "rotate")
  near(createVector(0, 2):heading(), HALF_PI, "heading") near(createVector(1, 0):dist(createVector(4, 4)), 5, "dist")
  near(createVector(1, 2):dot(createVector(3, 4)), 11, "dot") near(PVector.fromAngle(0).x, 1, "fromAngle")
  near(PVector.random2D():mag(), 1, "random2D") assert(createVector(1, 2) == createVector(1, 2))
  near(createVector(0, 0):lerp(createVector(10, 20), 0.5).y, 10, "lerp") near(PVector.angleBetween(createVector(1, 0), createVector(0, 1)), HALF_PI, "angle")
  assert(tostring(createVector(1, 2)):find("1"), "tostring")

  -- curves, strings, time
  near(bezierPoint(0, 0, 10, 10, 0.5), 5, "bezierPoint") near(curvePoint(0, 0, 10, 10, 0.5), 5, "curvePoint")
  near(bezierPoint(1, 2, 3, 4, 0), 1, "bezierPoint at 0") near(bezierTangent(0, 10, 20, 30, 0.5), 30, "bezierTangent")
  assert(trim("  hi \n") == "hi") assert(join({ "a", "b" }, "-") == "a-b")
  local parts = split("a,b,,c", ",") assert(#parts == 4 and parts[3] == "" and parts[4] == "c", "split")
  assert(#split("abc", "") == 3 and split("a.b", ".")[2] == "b", "split is plain text")
  assert(nf(7, 3) == "007" and nf(3.14159, 1, 2) == "3.14" and nf(-5, 3) == "-005", "nf")
  assert(saveStrings("lines.txt", { "one", "two", 3 })) local lines = loadStrings("lines.txt")
  assert(#lines == 3 and lines[2] == "two" and lines[3] == "3", "strings round trip") assert(loadStrings("nope.txt") == nil)
  assert(year() > 2020 and month() >= 1 and month() <= 12 and day() >= 1 and day() <= 31)
  assert(hour() >= 0 and hour() < 24 and minute() < 60 and second() < 61)
  save("saved.png") assert(io.open("saved.png")) 
  print("ok") exit()
end
