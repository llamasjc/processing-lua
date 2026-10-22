-- windowMoved / windowResized are called when the window moves or changes size
-- stdout: ok
local moved, resized = 0, 0
function windowMoved() moved = moved + 1 end
function windowResized() resized = resized + 1 end
function focusGained() end
function focusLost() end
function mouseEntered() end
function mouseExited() end
function setup() size(120, 100) end
function draw()
  if frameCount == 5 then windowMove(40, 60) end
  if frameCount == 10 then windowResize(160, 90) end
  if frameCount == 30 then
    assert(resized >= 1, "windowResized: " .. resized)
    assert(moved >= 1, "windowMoved: " .. moved)
    print("ok") exit()
  end
end
