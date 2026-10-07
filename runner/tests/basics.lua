-- stdout: setup width=320 height=200
-- stdout: first frame 1
-- stdout: done
local frames = 0
function setup()
  size(320, 200)
  assert(math.type(width) == "integer" and math.type(height) == "integer", "width/height are integers")
  print("setup width=" .. width .. " height=" .. height)
  assert(frameCount == 0, "frameCount is 0 in setup")
end

function draw()
  frames = frames + 1
  if frames == 1 then print("first frame " .. frameCount) end
  assert(frameCount == frames, "frameCount counts draws from 1")
  assert(width == 320 and height == 200, "size sticks")
  assert(math.type(mouseX) == "integer", "mouseX is an integer")
  assert(type(frameRate) == "number", "frameRate reads as a number")
  background(10, 20, 30)
  local r, g, b = get(5, 5)
  assert(r == 10 and g == 20 and b == 30, "background color: " .. r .. "," .. g .. "," .. b)
  if frames == 5 then print("done") exit() end
end
