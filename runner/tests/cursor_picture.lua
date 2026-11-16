-- cursor(img), cursor(img, x, y), WAIT and MOVE work; images never look like a cursor kind
-- stdout: ok
local frames = 0
function setup()
  size(100, 100)
  local pic = createImage(16, 16, ARGB)
  assert(pic >= 65536, "image numbers start high: " .. pic)
  cursor(pic)
  cursor(pic, 2, 3)
  cursor(WAIT) cursor(MOVE) cursor(HAND) cursor(pic) cursor()
end
function draw()
  frames = frames + 1
  if frames == 5 then print("ok") exit() end
end
