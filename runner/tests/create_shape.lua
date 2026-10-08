-- createShape: shapes built in code
-- stdout: ok
local function px(x, y) local r, g, b = get(x, y) return r .. "," .. g .. "," .. b end
function setup() size(200, 160) noLoop() end
function draw()
  noSmooth() noStroke()
  -- a primitive draws with the current style, where shape() puts it
  local box = createShape(RECT, 0, 0, 40, 20)
  background(0) fill(255, 0, 0) shape(box, 10, 10) fill(0, 255, 0) shape(box, 100, 100)
  assert(px(20, 20) == "255,0,0" and px(120, 110) == "0,255,0" and px(60, 20) == "0,0,0", "primitive, current style")
  -- its own style wins, and does not leak into the sketch
  box:fill(0, 0, 255) background(0) fill(255) shape(box, 10, 10) rect(100, 100, 10, 10)
  assert(px(20, 20) == "0,0,255" and px(105, 105) == "255,255,255", "own style, not leaked")
  box:setFill(color(255, 255, 0)) background(0) shape(box, 10, 10) assert(px(20, 20) == "255,255,0", "setFill replaces")
  box:disableStyle() background(0) fill(9) shape(box, 10, 10) assert(px(20, 20) == "9,9,9", "disableStyle") box:enableStyle()
  -- vertices
  local tri = createShape() tri:beginShape() tri:fill(255, 0, 255) tri:vertex(0, 0) tri:vertex(60, 0) tri:vertex(0, 60) tri:endShape(CLOSE)
  background(0) shape(tri, 20, 20) assert(px(30, 30) == "255,0,255" and px(70, 70) == "0,0,0", "vertices")
  assert(tri:getVertexCount() == 3) local vx, vy = tri:getVertex(1) assert(vx == 60 and vy == 0)
  tri:setVertex(1, 60, 60) background(0) shape(tri, 20, 20) assert(px(60, 70) == "255,0,255" and px(70, 30) == "0,0,0", "setVertex moves a corner")
  assert(not pcall(tri.getVertex, tri, 9) and not pcall(tri.setVertex, tri, -1, 0, 0))
  -- the shape's own transform adds to the sketch's
  local bar = createShape(RECT, 0, 0, 40, 10) bar:fill(255) bar:rotate(HALF_PI)
  background(0) shape(bar, 100, 50) assert(px(95, 70) == "255,255,255" and px(120, 55) == "0,0,0", "rotated shape")
  bar:resetMatrix() bar:translate(10, 0) bar:scale(2) background(0) shape(bar, 0, 100) assert(px(80, 110) == "255,255,255" and px(5, 105) == "0,0,0", "translate + scale")
  -- groups, with a loaded SVG as a child too
  local g = createShape(GROUP) local a, b = createShape(ELLIPSE, 20, 20, 20, 20), createShape(RECT, 50, 10, 20, 20)
  a:fill(255, 0, 0) b:fill(0, 255, 0) g:addChild(a) g:addChild(b)
  g:addChild(loadShape(os.getenv("LUAMODE_TESTS") .. "/assets/drawing.svg"))
  assert(g:getChildCount() == 3 and g:getChild(0) == a and tostring(g):find("group"))
  background(0) shape(g, 0, 0) assert(px(20, 20) == "255,0,0" and px(60, 20) == "0,255,0" and px(135, 25) == "0,0,255", "group draws its children")
  g:translate(0, 60) background(0) shape(g, 0, 0) assert(px(20, 80) == "255,0,0" and px(20, 20) == "0,0,0", "moving a group moves all of it")
  assert(not pcall(g.addChild, g, g) and not pcall(g.addChild, g, 5), "bad children")
  local inner = createShape(GROUP) g:addChild(inner) assert(not pcall(inner.addChild, inner, g), "no loops")
  -- misuse
  local s = createShape() assert(not pcall(s.vertex, s, 1, 2), "vertex before beginShape")
  s:beginShape() s:vertex(0, 0) shape(s, 0, 0)                 -- unfinished: draws nothing, breaks nothing
  assert(not pcall(createShape, 999)) assert(not pcall(shape, {}, 0, 0))
  shape(createShape(), 0, 0) shape(createShape(GROUP)) shape(createShape(ARC, 50, 50, 40, 40, 0, PI), 0, 0)
  shape(createShape(LINE, 0, 0, 10, 10), 0, 0) shape(createShape(TRIANGLE, 0, 0, 10, 0, 0, 10), 0, 0) shape(createShape(QUAD, 0, 0, 10, 0, 10, 10, 0, 10), 0, 0)
  -- the sketch's own transform and style are as they were
  fill(1, 2, 3) rect(0, 150, 5, 5) assert(px(2, 152) == "1,2,3", "nothing leaked")
  print("ok") exit()
end
