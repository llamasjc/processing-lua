-- stdout: img 4 2 255 0 true
-- stdout: crop 2 2 255 0
-- stdout: resize 8 4
-- stdout: mask 128
-- stdout: region 20 20 255 136
-- stdout: saved true 8
-- stdout: px 32 0 true
-- stdout: fmt 1,234,567 -1,000 1,234.50 +05  05 3
function setup()
  size(100, 100)
  local img = createImage(4, 2)
  imageSet(img, 1, 1, color(255, 0, 0))
  local c = imageGet(img, 1, 1)
  print(string.format("img %d %d %d %d %s", imageWidth(img), imageHeight(img), red(c), alpha(imageGet(img, 50, 50)), tostring(red(imageGet(img, 1, 1)) == 255)))
  local crop = imageGet(img, 1, 0, 2, 2)
  print(string.format("crop %d %d %d %d", imageWidth(crop), imageHeight(crop), red(imageGet(crop, 0, 1)), alpha(imageGet(crop, 1, 0))))
  imageResize(img, 8)
  print(string.format("resize %d %d", imageWidth(img), imageHeight(img)))
  local m = createImage(8, 4)
  local px = imagePixels(m)
  for i = 1, #px do px[i] = color(128) end
  imageSetPixels(m, px)
  local b = imageCopy(img)
  imageSet(b, 0, 0, color(0, 255, 0))
  imageMask(b, m)
  print(string.format("mask %d", math.floor(alpha(imageGet(b, 0, 0)) + 0.5)))
  local back = imagePixels(img)
  imageSetPixels(img, back)
  local same, clear = 0, 0
  for i, p in ipairs(imagePixels(img)) do
    if p == back[i] then same = same + 1 end
    if alpha(p) == 0 then clear = clear + 1 end
  end
  print(string.format("px %d %d %s", #back, #back - same, clear > 0))
  print("fmt " .. table.concat({nfc(1234567), nfc(-1000), nfc(1234.5, 2), nfp(5, 2), nfs(5, 2), #splitTokens("a, b  c", ", ")}, " "))
  background(0)
  fill(255, 136, 0)
  noStroke()
  rect(10, 10, 40, 40)
  local piece = get(10, 10, 20, 20)
  local pc = imageGet(piece, 5, 5)
  print(string.format("region %d %d %d %d", imageWidth(piece), imageHeight(piece), red(pc), green(pc)))
  local path = os.getenv("TMPDIR") or "/tmp"
  path = path .. "/luamode-img-test.png"
  local ok = saveImage(b, path)
  print(string.format("saved %s %d", tostring(ok), imageWidth(loadImage(path))))
  exit()
end
