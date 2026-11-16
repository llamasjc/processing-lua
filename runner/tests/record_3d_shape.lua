-- a shape made with vertex(x, y, z) is recorded where the camera shows it, not flattened
-- stdout: ok
function setup() size(200, 200, P3D) noLoop() end
function draw()
  local path = "rec3d.svg"
  beginRecord(SVG, path)
  background(255) fill(255, 0, 0) noStroke()
  beginShape() vertex(50, 50, -400) vertex(150, 50, -400) vertex(150, 150, -400) vertex(50, 150, -400) endShape(CLOSE)
  endRecord()
  local f = io.open(path) local svg = f:read("a") f:close() os.remove(path)
  -- far away, the square is drawn smaller than 100 across, around the middle
  local xs = {}
  for x in svg:gmatch("M%s*([%d%.%-]+)") do xs[#xs + 1] = tonumber(x) end
  for x in svg:gmatch("L%s*([%d%.%-]+)") do xs[#xs + 1] = tonumber(x) end
  assert(#xs >= 4, "a path: " .. svg:sub(1, 300))
  local lo, hi = math.huge, -math.huge
  for _, x in ipairs(xs) do lo = math.min(lo, x) hi = math.max(hi, x) end
  assert(hi - lo < 90 and lo > 50, "drawn smaller, toward the middle: " .. lo .. ".." .. hi)
  print("ok") exit()
end
