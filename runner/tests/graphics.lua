-- createGraphics: off-screen layers
-- stdout: ok
local pg, small
function setup()
  size(100, 80)
  pg = createGraphics(40, 30)
  small = createGraphics(10, 10)
  assert(pg.width == 40 and pg.height == 30)
  noLoop()
end
function draw()
  background(0, 0, 255)
  -- draw on the layer; the canvas must not change meanwhile
  pg:beginDraw()
  assert(width == 40 and height == 30, "width/height describe the layer")
  pg:noStroke() pg:fill(255, 0, 0) pg:rect(0, 0, 20, 30)       -- left half red, right half untouched
  fill(0, 255, 0, 128) rect(20, 0, 10, 30)                      -- plain calls go to the layer too
  local r, g, b = get(5, 5) assert(r == 255 and b == 0, "get reads the layer")
  pg:endDraw()
  assert(width == 100 and height == 80, "width/height are the canvas again")
  local r, g, b = get(5, 5) assert(r == 0 and b == 255, "canvas untouched by layer drawing")

  image(pg, 10, 10)
  r, g, b = get(15, 15) assert(r == 255 and g == 0 and b == 0, "opaque part drawn")
  r, g, b = get(35, 15) assert(g > 100 and g < 160 and b > 100 and b < 160, "half transparent part blends with the canvas: " .. g .. "," .. b)
  r, g, b = get(45, 15) assert(r == 0 and b == 255, "untouched part of the layer is transparent")
  r, g, b = get(60, 60) assert(b == 255, "outside the layer")

  -- scaled, centred, tinted
  background(0) imageMode(CENTER) image(pg, 50, 40, 80, 60) imageMode(CORNER)
  r = get(20, 40) assert(r == 255, "scaled")
  background(0) tint(255, 128) image(pg, 0, 0) noTint() r = get(5, 5) assert(r > 100 and r < 160, "tint fades a layer: " .. r)

  -- the layer keeps its picture and its own style between frames
  pg:beginDraw() pg:rect(30, 0, 10, 10) pg:endDraw()          -- still the green fill from before, no stroke
  background(0) image(pg, 0, 0) r, g, b = get(35, 5) assert(g > 100 and r == 0, "layer remembers its fill")
  fill(9) rect(60, 60, 5, 5) r = get(62, 62) assert(r == 9, "canvas style is its own")

  -- clear, nesting, and things that must not break anything
  pg:beginDraw() clear() pg:endDraw() background(0, 0, 255) image(pg, 0, 0) r, g, b = get(5, 5) assert(b == 255 and r == 0, "clear() empties a layer")
  pg:beginDraw() small:beginDraw() background(255) small:endDraw() image(small, 0, 0) pg:endDraw()
  background(0) image(pg, 0, 0) r = get(5, 5) assert(r == 255, "a layer drawn into a layer")
  assert(not pcall(function() pg:beginDraw() pg:beginDraw() end), "beginDraw twice is an error")
  pg:endDraw() pg:endDraw() pg:endDraw()                        -- extra endDraw: nothing happens
  pg:beginDraw() image(pg, 0, 0) pg:endDraw()                   -- a layer onto itself: ignored
  assert(not pcall(createGraphics, 0, 10)) assert(not pcall(createGraphics, "x", 10))
  assert(tostring(pg) == "layer 40x30")
  pg:beginDraw()                                                -- left open on purpose
  print("ok") exit()
end
