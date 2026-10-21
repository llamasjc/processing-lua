-- clip / noClip, push / pop, hint(DISABLE_DEPTH_TEST), loadJSONObject /
-- loadJSONArray, saveStream, launch
-- stdout: ok
function setup() size(120, 100) noLoop() end
function draw()
  noStroke() background(0)
  -- only the clip rectangle takes the drawing
  clip(20, 20, 40, 30) fill(255, 0, 0) rect(0, 0, 120, 100) noClip()
  local r = get(30, 30) assert(r == 255, "inside the clip: " .. r)
  r = get(10, 10) assert(r == 0, "outside the clip stays: " .. r)
  r = get(70, 30) assert(r == 0, "right of the clip stays: " .. r)
  -- it follows translate, and imageMode(CENTER) places it
  background(0) push() translate(50, 50) imageMode(CENTER) clip(0, 0, 20, 20) imageMode(CORNER)
  fill(0, 255, 0) rect(-50, -50, 120, 100) noClip() pop()
  local _, g = get(50, 50) assert(g == 255, "translated clip, inside: " .. g)
  _, g = get(30, 30) assert(g == 0, "translated clip, outside: " .. g)
  -- push/pop bring back the fill and the transform
  background(0) fill(0, 0, 255) push() fill(255) translate(100, 100) pop() rect(0, 0, 10, 10)
  local _, _, b = get(5, 5) assert(b == 255, "pop restored fill and transform: " .. b)
  -- hint(DISABLE_DEPTH_TEST): later shapes draw over nearer ones (the
  -- software renderer; libprocessing always tests depth)
  if os.getenv("PROCESSING_RENDERER") ~= "libprocessing" then
  background(0) lights() hint(DISABLE_DEPTH_TEST)
  translate(60, 50, 0)
  fill(255, 0, 0) push() translate(0, 0, 20) box(30) pop()
  fill(0, 0, 255) push() translate(0, 0, -20) box(30) pop()
  hint(ENABLE_DEPTH_TEST) noLights()
  local rr, _, bb = get(60, 50) assert(bb > rr, "the far box drew last and shows: " .. rr .. "," .. bb)
  end
  resetMatrix()
  -- JSON by Processing's names
  local dir = os.getenv("LUAMODE_TESTS") .. "/assets/"
  saveJSON("o.json", { a = 1 }) saveJSON("l.json", { 1, 2, 3 })
  assert(loadJSONObject("o.json").a == 1 and loadJSONObject("l.json") == nil, "loadJSONObject")
  assert(#loadJSONArray("l.json") == 3 and loadJSONArray("o.json") == nil, "loadJSONArray")
  assert(parseJSONArray("[1,2]")[2] == 2 and parseJSONObject("[1]") == nil, "parseJSON...")
  -- saveStream copies a file; launch says when it can't
  assert(saveStream("copy.json", "o.json") and loadJSONObject("copy.json").a == 1, "saveStream")
  assert(launch("no-such-program-anywhere") == false, "launch of nothing")
  print("ok") exit()
end
