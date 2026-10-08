-- filter(), JSON, per-corner rects, fullScreen, number formatting
-- stdout: ok
-- stdout: [2] b
-- stderr: missing.json
-- stderr: broken.json
-- env: PROCESSING_DISPLAY=0,0,0,0
local function near(a, b, what) assert(math.abs(a - b) <= 2, what .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
function setup() size(60, 40) noLoop() end
function draw()
  -- filters
  background(200, 100, 50) filter(INVERT) local r, g, b = get(5, 5) assert(r == 55 and g == 155 and b == 205, "INVERT")
  background(200, 100, 50) filter(GRAY) r, g, b = get(5, 5) assert(r == g and g == b and r > 110 and r < 130, "GRAY " .. r)
  background(200, 100, 50) filter(THRESHOLD) r = get(5, 5) assert(r == 255, "THRESHOLD: bright") 
  background(100, 60, 50) filter(THRESHOLD) r = get(5, 5) assert(r == 0, "THRESHOLD: dark")
  background(100, 60, 50) filter(THRESHOLD, 0.2) r = get(5, 5) assert(r == 255, "THRESHOLD level")
  background(130, 10, 250) filter(POSTERIZE, 2) r, g, b = get(5, 5) assert(r == 255 and g == 0 and b == 255, "POSTERIZE " .. r .. "," .. g .. "," .. b)
  background(0) noStroke() fill(255) rect(20, 10, 20, 20) filter(BLUR, 3)
  r = get(30, 20) assert(r > 200, "BLUR: middle stays bright " .. r) r = get(18, 20) assert(r > 10 and r < 200, "BLUR: edge spreads " .. r)
  r = get(2, 2) assert(r < 10, "BLUR: far away stays dark")
  background(0) fill(255) rect(20, 10, 20, 20) filter(ERODE) r = get(20, 20) assert(r == 0, "ERODE shrinks") r = get(22, 20) assert(r == 255)
  background(0) fill(255) rect(20, 10, 20, 20) filter(DILATE) r = get(19, 20) assert(r == 255, "DILATE grows") r = get(17, 20) assert(r == 0)
  filter(OPAQUE) filter(99) filter(BLUR, 0/0) filter(BLUR, -5) filter(BLUR, 1e9) filter(POSTERIZE, 0/0) filter(POSTERIZE, 1e9)
  -- a filter on a layer keeps its transparency
  local pg = createGraphics(20, 20) pg:beginDraw() pg:fill(255, 0, 0) pg:noStroke() pg:rect(0, 0, 10, 20) pg:filter(INVERT) pg:endDraw()
  background(0, 255, 0) image(pg, 0, 0) r, g, b = get(5, 5) assert(r == 0 and g == 255 and b == 255, "layer INVERT: cyan " .. r .. g .. b)
  r, g, b = get(15, 5) assert(g == 255 and r == 0 and b == 0, "layer INVERT: empty part still transparent")

  -- rect with a radius per corner: only the top-left is rounded here
  noSmooth() background(0) fill(255) rect(10, 5, 40, 30, 12, 0, 0, 0)
  assert(get(10, 5) == 0 and get(49, 5) == 255 and get(49, 34) == 255 and get(10, 34) == 255 and get(30, 20) == 255, "per-corner radii")
  rect(0, 0, 10, 10, 0, 0, 0, 0) rect(0, 0, 10, 10, 1e9, -5, 0/0, 3) smooth()

  -- JSON
  local v = parseJSON('{"name": "caf\\u00e9", "list": [1, 2.5, -3e2, true, false, null, "x"], "deep": {"a": {"b": []}}, "n": null}')
  assert(v.name == "caf\xC3\xA9" and v.list[1] == 1 and v.list[2] == 2.5 and v.list[3] == -300 and v.list[4] == true and v.list[5] == false)
  assert(v.list[6] == nil and v.list[7] == "x" and type(v.deep.a.b) == "table" and v.n == nil)
  assert(math.type(parseJSON("42")) == "integer" and parseJSON(' "hi" ') == "hi" and parseJSON("[]")[1] == nil)
  assert(parseJSON('"\\ud83d\\ude00"') == "\xF0\x9F\x98\x80", "surrogate pair")
  for _, bad in ipairs { "", "{", "[1,]", '{"a" 1}', "nope", "[1] x", '"abc', '{"a":}', "[" .. string.rep("[", 500) } do
    local ok, why = pcall(parseJSON, bad) assert(not ok and tostring(why):find("JSON"), "rejects " .. bad:sub(1, 10))
  end
  local ok, why = pcall(parseJSON, '{\n"a": 1,\n"b" 2}') assert(tostring(why):find("line 3"), "says which line: " .. tostring(why))
  local text = toJSON({ name = "a\"b\n", list = { 1, 2, { x = 1.5 } }, empty = {}, flag = true })
  local back = parseJSON(text)
  assert(back.name == "a\"b\n" and back.list[3].x == 1.5 and #back.list == 3 and back.flag == true and #back.empty == 0, "round trip")
  assert(toJSON({ b = 1, a = 2 }) == toJSON({ a = 2, b = 1 }), "same table, same text")
  assert(toJSON(0/0) == "null" and toJSON("x") == '"x"' and toJSON(3) == "3")
  local loop = {} loop.me = loop assert(not pcall(toJSON, loop), "a table inside itself") assert(not pcall(toJSON, print))
  assert(saveJSON("out.json", { score = 12, tags = { "a", "b" } })) local loaded = loadJSON("out.json")
  assert(loaded.score == 12 and loaded.tags[2] == "b", "file round trip")
  assert(loadJSON("missing.json") == nil)
  local f = io.open("broken.json", "w") f:write("{ nope") f:close() assert(loadJSON("broken.json") == nil)

  -- numbers as text
  assert(hex(255) == "FF" and hex(255, 6) == "0000FF" and hex(0x12345, 2) == "45" and unhex("FF") == 255 and unhex("zz") == 0)
  assert(binary(5) == "101" and binary(5, 8) == "00000101" and unbinary("101") == 5 and hex(color(255, 0, 0)) == "FFFF0000")
  printArray({ "a", "b" }) printArray("not a list")

  -- environment
  assert(type(focused) == "boolean" and displayWidth == 0 and displayHeight == 0, "no screen info given")
  print("ok") exit()
end
