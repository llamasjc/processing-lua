-- drawing on a layer every frame doesn't freeze the main canvas
-- stdout: ok
local layer
function setup() size(200, 100) layer = createGraphics(200, 100) end
function draw()
  background(0, 0, 255) noStroke()
  fill(255, 0, 0) rect(frameCount * 20, 10, 15, 15)
  layer:beginDraw() layer:noStroke() layer:fill(0, 255, 0) layer:ellipse(150, 70, 10, 10) layer:endDraw()
  image(layer, 0, 0)
  if frameCount == 4 then
    local r = get(4 * 20 + 7, 17)
    local r1 = get(1 * 20 + 7, 17)
    assert(r > 200, "this frame's square: " .. r)
    assert(r1 < 50, "frame 1's square is gone: " .. r1)
    print("ok") exit()
  end
end
