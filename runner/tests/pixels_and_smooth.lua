-- loadPixels/updatePixels and smooth()/noSmooth()
-- stdout: ok
function setup() size(40, 30) noLoop() end
function draw()
  background(10, 20, 30)
  loadPixels()
  assert(pixels[0] == color(10, 20, 30) and pixels[40 * 30 - 1] == color(10, 20, 30), "loaded")
  assert(pixels[40 * 30] == nil, "exactly width * height entries")
  pixels[5 * width + 7] = color(200, 100, 50)
  pixels[0] = 255            -- a plain gray
  pixels[1] = nil            -- left alone
  updatePixels()
  local r, g, b = get(7, 5) assert(r == 200 and g == 100 and b == 50, "written back")
  r, g, b = get(0, 0) assert(r == 255 and g == 255 and b == 255, "gray entry")
  r, g, b = get(1, 0) assert(r == 10 and b == 30, "nil entry keeps the pixel")
  local same = pixels loadPixels() assert(pixels == same, "table is reused")

  -- smooth: a slanted edge has in-between pixels; noSmooth has none
  local function shades()
    background(0) noStroke() fill(255) triangle(2, 2, 38, 10, 2, 28)
    local n = 0
    for y = 0, 29 do for x = 0, 39 do local v = get(x, y) if v > 0 and v < 255 then n = n + 1 end end end
    return n
  end
  smooth() assert(shades() > 10, "smooth edges blend")
  noSmooth() assert(shades() == 0, "noSmooth edges are hard")
  smooth()
  -- interiors stay exact, axis-aligned shapes stay crisp
  background(0) fill(255) rect(10, 10, 10, 10)
  assert(get(15, 15) == 255 and get(10, 10) == 255 and get(19, 19) == 255 and get(9, 10) == 0 and get(20, 15) == 0, "crisp rect")
  -- a horizontal hairline is one crisp row
  background(0) stroke(255) strokeWeight(1) line(5, 20, 30, 20)
  assert(get(10, 20) == 255 and get(10, 19) == 0 and get(10, 21) == 0, "crisp hairline")
  -- translucent smooth fill: inside is the plain blend
  background(0) noStroke() fill(255, 128) ellipse(20, 15, 20, 20)
  local v = get(20, 15) assert(v >= 127 and v <= 129, "translucent inside: " .. v)
  print("ok") exit()
end
