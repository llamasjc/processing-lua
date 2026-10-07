-- rc: 124
-- timeout: 3
-- stdout: draw 1
-- stderr-lines: 0
local draws = 0
function setup() noLoop() end
function draw()
  draws = draws + 1
  print("draw " .. draws)
  assert(draws == 1, "noLoop() means draw() runs once")
end
