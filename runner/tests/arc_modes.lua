-- arc() with no mode fills a pie and outlines only the curve; PIE outlines through the center
-- stdout: ok
function setup() size(240, 120) noLoop() end
function draw()
  background(0) stroke(255) strokeWeight(4) fill(255, 150, 40)
  arc(60, 60, 90, 90, 0, 4.5)
  arc(180, 60, 90, 90, 0, 4.5, PIE)
  -- inside the missing wedge's corner, near the center: filled (pie) for neither
  local r = get(60 + 8, 60 - 20)
  assert(r < 60, "plain arc: the cut-out wedge stays empty: " .. r)
  -- the plain arc has no line from the center out to the start
  r = get(60 + 30, 60)
  assert(r > 200 and select(2, get(60 + 30, 60)) < 200, "plain arc: fill, not an outline, along the start edge")
  -- PIE has its outline along the start edge
  local g = select(2, get(180 + 30, 60))
  assert(g > 200, "PIE: outline along the start edge: " .. g)
  print("ok") exit()
end
