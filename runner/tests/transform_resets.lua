-- stdout: ok
-- translate() in draw must not pile up from frame to frame, and a missing
-- popMatrix/popStyle must not leak into the next one.
function setup() size(200, 100) end
function draw()
  background(0)
  noStroke()
  fill(255, 0, 0)
  translate(20, 20)
  pushMatrix()            -- never popped, on purpose
  pushStyle()             -- never popped, on purpose
  rect(0, 0, 10, 10)
  local r = get(25, 25)
  assert(r == 255, "frame " .. frameCount .. ": rect should be at 20,20")
  local r2 = get(65, 65)
  assert(r2 == 0, "frame " .. frameCount .. ": nothing at 60,60")
  if frameCount == 6 then print("ok") exit() end
end
