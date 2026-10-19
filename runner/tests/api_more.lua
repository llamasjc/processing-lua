-- lights and materials, curve detail, shapeMode, copy, XML, writers, arrays, regex, threads
-- stdout: ok
local function px(x, y)
  local r, g, b = get(x, y)
  local function snap(v) for _, t in ipairs({0, 255}) do if math.abs(v - t) <= 12 then return t end end return v end
  return snap(r) .. "," .. snap(g) .. "," .. snap(b)
end
local stepped = 0
function work() for i = 1, 3 do stepped = i coroutine.yield() end end
function setup() size(200, 160) thread("work") end
function draw()
  if frameCount < 4 then return end
  -- a spot light lights on every frame, not just the one it was made in
  if frameCount < 6 then
    noStroke() background(0) fill(255)
    spotLight(255, 255, 255, 50, 80, 300, 0, 0, -1, PI / 16, 1) rect(0, 0, 200, 160) noLights()
    local c, far = get(50, 80), get(180, 20)
    assert(c > 100 and far < 20, "spot light on frame " .. frameCount .. ": " .. c .. " " .. far)
    return
  end
  assert(stepped == 3, "thread ran a step a frame: " .. stepped)
  noStroke()
  -- a spot light only lights its cone
  background(0) fill(255)
  spotLight(255, 255, 255, 50, 80, 300, 0, 0, -1, PI / 16, 1)
  rect(0, 0, 200, 160)
  noLights()
  local r1 = get(50, 80) local r2 = get(180, 20)
  assert(r1 > 100 and r2 < 20, "spot light: " .. r1 .. " " .. r2)
  -- emissive glows without light
  background(0) lights() ambientLight(0, 0, 0) emissive(0, 200, 0) fill(0) rect(0, 0, 50, 50) noLights() emissive(0)
  local _, g = get(25, 25) assert(g > 150, "emissive: " .. g)
  -- shapeMode(CENTER) on a shape made in code
  background(0)
  local box = createShape() box:beginShape() box:fill(255, 0, 0) box:vertex(0, 0) box:vertex(20, 0) box:vertex(20, 20) box:vertex(0, 20) box:endShape(CLOSE)
  shapeMode(CENTER) shape(box, 100, 80) shapeMode(CORNER)
  assert(px(100, 80) == "255,0,0" and px(92, 72) == "255,0,0" and px(112, 80) == "0,0,0", "shapeMode CENTER")
  -- copy a corner somewhere else, bigger
  background(0) fill(0, 0, 255) rect(0, 0, 10, 10)
  copy(0, 0, 10, 10, 100, 100, 40, 40)
  assert(px(130, 130) == "0,0,255" and px(90, 130) == "0,0,0", "copy: " .. px(130, 130))
  -- curve tightness 1 is straight lines through the points
  assert(math.abs(curvePoint(0, 10, 20, 30, 0.5) - 15) < 1e-4)
  curveTightness(1) assert(math.abs(curvePoint(0, 10, 50, 0, 0.5) - 30) < 1e-4, "tight curve is a straight line") curveTightness(0)
  bezierDetail(4) curveDetail(4)
  -- XML
  local x = parseXML('<root v="2"><item n="a">one</item><item n="b">two &amp; three</item><g><h k="1.5"/></g></root>')
  assert(x:getName() == "root" and x:getInt("v") == 2 and #x:getChildren("item") == 2, "xml")
  assert(x:getChild("item"):getContent() == "one" and x:getChildren("item")[2]:getContent() == "two & three")
  assert(x:getChild("g/h"):getFloat("k") == 1.5 and x:getChild(0):getString("n") == "a")
  local y = XML("list") y:addChild("e"):setString("k", "v")
  local back = parseXML(y:format(2)) assert(back:getChild("e"):getString("k") == "v", "xml round trip")
  assert(parseXML("<a><b></a>") == nil, "broken xml")
  saveXML(x, "out.xml") assert(loadXML("out.xml"):getChild("g/h"):getFloat("k") == 1.5, "saveXML/loadXML")
  -- writer and reader
  local w = createWriter("sub/lines.txt") w:println("first", 2) w:print("second") w:close()
  local r = createReader("sub/lines.txt") assert(r:readLine() == "first 2" and r:readLine() == "second" and r:readLine() == nil, "reader") r:close()
  -- arrays
  local a = append({1, 2}, 3) assert(#a == 3 and a[3] == 3)
  assert(#shorten(a) == 2 and concat({1}, {2, 3})[3] == 3 and subset({1, 2, 3, 4}, 2, 2)[2] == 3)
  assert(table.concat(splice({1, 4}, {2, 3}, 2), ",") == "1,2,3,4" and table.concat(sort({3, 1, 2}), ",") == "1,2,3")
  assert(table.concat(reverse({1, 2, 3}), ",") == "3,2,1")
  local dst = {} arrayCopy({7, 8}, dst) assert(dst[2] == 8)
  -- regular expressions, like Processing's match
  local m = match("size: 300px", "(\\d+)px") assert(m and m[2] == "300", "match")
  assert(match("abc", "\\d") == nil and #matchAll("a1 b2 c3", "([a-z])(\\d)") == 3, "matchAll")
  assert(displayDensity() == 1 and pixelWidth() == width)
  print("ok") exit()
end
