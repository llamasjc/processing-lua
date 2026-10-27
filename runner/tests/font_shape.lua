-- font:getShape(c): a character's outline as a shape
-- stdout: ok
function setup() size(120, 120) noLoop() end
function draw()
  local f = createFont("DejaVu Sans", 100)
  if f == 0 then f = createFont("sans-serif", 100) end
  if f == 0 then print("ok") exit() return end   -- no font on this machine
  local o = f:getShape("O")
  assert(o:getVertexCount() >= 2, "outline has its two contours")
  background(0) noStroke() fill(255)
  shape(o, 10, 100)
  -- the ring is filled, the hole isn't
  local w = f:width("O") * 100
  local r = get(math.floor(10 + w / 2), 60) assert(r < 50, "hole in the middle: " .. r)
  local found = false
  for x = 10, 60 do if get(x, 60) > 200 then found = true break end end
  assert(found, "the ring is filled")
  print("ok") exit()
end
