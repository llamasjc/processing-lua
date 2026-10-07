-- a layer left open at the end of setup() or draw() must not become the window
-- stdout: ok
local pg
function setup() size(120, 90) pg = createGraphics(20, 20) pg:beginDraw() end
function draw()
  assert(width == 120 and height == 90, "frame " .. frameCount .. ": " .. width .. "x" .. height)
  background(255) local r = get(100, 80) assert(r == 255, "drawing reaches the whole canvas")
  pg:beginDraw() pg:background(0)
  if frameCount == 4 then print("ok") exit() end
end
function mousePressed() pg:beginDraw() end
