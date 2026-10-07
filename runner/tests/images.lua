-- stdout: ok
-- stderr: missing.png
function setup() size(60, 60) noLoop() end
function draw()
  background(0, 0, 255)
  saveFrame("shot.png")
  local img = loadImage("shot.png")
  assert(img ~= 0, "image saved and loaded back")
  background(0)
  image(img, 0, 0)
  local r, g, b = get(30, 30)
  assert(b == 255 and r == 0, "image drawn: " .. r .. "," .. g .. "," .. b)
  image(img, 10, 10, 20, 20) image(img, 0, 0, 0, 0) image(img, 0, 0, -10, 1e9)
  tint(255, 0, 0) image(img, 0, 0) noTint()
  local missing = loadImage("missing.png")      -- complains on stderr, returns 0
  assert(missing == 0)
  image(missing, 0, 0) image(12345, 0, 0) image(-1, 0, 0)
  saveFrame("no/such/folder/x.png")              -- complains, carries on
  saveFrame("frame-####.png") saveFrame()
  print("ok") exit()
end
