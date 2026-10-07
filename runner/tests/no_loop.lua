-- stdout: draw 1
-- stdout: draw 2
-- stdout: ok
-- noLoop() in setup still draws once; redraw() from an event draws once more.
-- With no real mouse here, a second sketch state is driven from top-level timing.
local draws = 0
function setup() size(100, 100) noLoop() end
function draw()
  draws = draws + 1
  print("draw " .. draws)
  if draws == 1 then redraw() end       -- asks for exactly one more
  if draws == 2 then loop() end
  if draws == 5 then print("ok") exit() end
end
