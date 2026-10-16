-- texture(), textureMode, textureWrap, 3D vertices, createShape BOX
-- stdout: ok
local function px(x, y) local r, g, b = get(x, y) return r .. "," .. g .. "," .. b end
function setup() size(200, 160) noLoop() end
function draw()
  noSmooth() noStroke()
  local img = createImage(2, 2)
  imageSet(img, 0, 0, color(255, 0, 0)) imageSet(img, 1, 0, color(0, 255, 0)) imageSet(img, 0, 1, color(0, 0, 255)) imageSet(img, 1, 1, color(255, 255, 0))
  background(0)
  textureMode(NORMAL)
  beginShape() texture(img)
  vertex(0, 0, 0, 0) vertex(100, 0, 1, 0) vertex(100, 100, 1, 1) vertex(0, 100, 0, 1)
  endShape()
  assert(px(20, 20) == "255,0,0" and px(80, 20) == "0,255,0" and px(20, 80) == "0,0,255" and px(80, 80) == "255,255,0", "textured quad: " .. px(20, 20) .. " " .. px(80, 20))
  -- IMAGE mode: u, v in pixels
  textureMode(IMAGE) background(0)
  beginShape(TRIANGLES) texture(img) vertex(0, 0, 0, 0) vertex(100, 0, 1, 0) vertex(0, 100, 0, 1) endShape()
  assert(px(10, 10) == "255,0,0", "IMAGE mode")
  -- REPEAT tiles the picture
  textureMode(NORMAL) textureWrap(REPEAT) background(0)
  beginShape() texture(img) vertex(0, 0, 0, 0) vertex(100, 0, 2, 0) vertex(100, 100, 2, 2) vertex(0, 100, 0, 2) endShape()
  assert(px(10, 10) == "255,0,0" and px(60, 10) == "255,0,0" and px(35, 10) == "0,255,0", "REPEAT")
  textureWrap(CLAMP)
  -- a 3D quad, facing the camera at z = 0, lands where a 2D one would
  background(0) fill(0, 255, 0)
  beginShape() vertex(50, 50, 0) vertex(150, 50, 0) vertex(150, 150, 0) vertex(50, 150, 0) endShape(CLOSE)
  assert(px(100, 100) == "0,255,0" and px(20, 20) == "0,0,0", "3D vertices")
  -- closer is bigger
  background(0) beginShape() vertex(90, 70, 50) vertex(110, 70, 50) vertex(110, 90, 50) vertex(90, 90, 50) endShape(CLOSE)
  assert(px(88, 80) == "0,255,0", "nearer quad looks bigger")
  -- createShape(BOX)
  local b = createShape(BOX, 40, 40, 40) b:fill(255, 0, 255)
  background(0) shape(b, 100, 80) assert(px(100, 80) == "255,0,255", "createShape(BOX)")
  print("ok") exit()
end
