-- lights added or cleared partway through a frame only light the shapes after it
-- stdout: ok
function setup() size(300, 100, P3D) noLoop() end
local function brightest(x0)
  local best, bc = -1, nil
  for x = x0 - 30, x0 + 30, 2 do for y = 20, 80, 2 do
    local r, g, b = get(x, y)
    if r + g + b > best then best, bc = r + g + b, { r, g, b } end
  end end
  return bc
end
function draw()
  background(0) noStroke() fill(255)
  directionalLight(255, 0, 0, 0, 0, -1)
  push() translate(50, 50) box(50) pop()
  directionalLight(0, 0, 255, 0, 0, -1)
  push() translate(150, 50) box(50) pop()
  noLights()
  directionalLight(0, 255, 0, 0, 0, -1)
  push() translate(250, 50) box(50) pop()
  local a, b, c = brightest(50), brightest(150), brightest(250)
  assert(a[1] > 150 and a[3] < 60, "first box: red only: " .. table.concat(a, ","))
  assert(b[1] > 150 and b[3] > 150, "second box: red and blue: " .. table.concat(b, ","))
  assert(c[2] > 150 and c[1] < 60 and c[3] < 60, "third box: green only: " .. table.concat(c, ","))
  print("ok") exit()
end
