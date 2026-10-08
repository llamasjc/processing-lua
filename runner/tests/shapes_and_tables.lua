-- loadShape (SVG) and loadTable (CSV)
-- stdout: ok
-- stderr: missing.svg
-- stderr: missing.csv
local assets = os.getenv("LUAMODE_TESTS") .. "/assets/"
local function px(x, y) local r, g, b = get(x, y) return r .. "," .. g .. "," .. b end
function setup() size(240, 160) noLoop() end
function draw()
  local s = loadShape(assets .. "drawing.svg")
  assert(s and s.width == 200 and s.height == 120, "size from the file")
  noSmooth() background(0) shape(s, 0, 0)
  assert(px(30, 25) == "255,0,0", "rect: " .. px(30, 25))
  assert(px(90, 25) == "0,255,0", "circle") assert(px(90, 5) == "0,0,0", "outside the circle")
  assert(px(135, 25) == "0,0,255", "group: translate and inherited fill")
  assert(px(175, 25) == "255,255,0", "style attribute wins") assert(px(160, 25) == "0,0,0", "stroke from style: " .. px(160, 25))
  assert(px(15, 65) == "255,0,255", "path") assert(px(30, 80) == "0,0,0", "hole in the path stays empty: " .. px(30, 80))
  assert(px(76, 82) == "255,255,255" or px(76, 83) == "255,255,255" or px(77, 82) == "255,255,255", "curve stroke")
  assert(px(90, 70) == "0,0,0", "fill none")
  assert(px(175, 92) == "0,127,127" or px(175, 92) == "0,128,128", "arc, half transparent: " .. px(175, 92))
  assert(px(90, 95) == "255,165,0", "polygon") assert(px(135, 110) == "255,0,0", "line")
  assert(px(100, 112) == "0,0,0", "display none") assert(px(5, 5) == "0,0,0", "defs are not drawn")
  -- scaled, and with the sketch's own style
  background(0) shape(s, 20, 20, 100, 60) assert(px(35, 32) == "255,0,0" and px(15, 15) == "0,0,0", "scaled into a box")
  s:disableStyle() background(0) fill(9, 8, 7) noStroke() shape(s, 0, 0) assert(px(30, 25) == "9,8,7" and px(90, 25) == "9,8,7", "disableStyle")
  s:enableStyle() background(0) shape(s, 0, 0) assert(px(30, 25) == "255,0,0", "enableStyle")
  -- it follows the transform
  background(0) push() translate(120, 80) rotate(PI) shape(s, 0, 0) pop() assert(px(90, 55) == "255,0,0", "half turn: " .. px(90, 55))
  smooth()
  -- bad input
  assert(loadShape("missing.svg") == nil) shape(nil, 0, 0) assert(not pcall(shape, 5, 0, 0))
  for name, text in pairs { ["empty.svg"] = "", ["notsvg.svg"] = "<html><body/></html>", ["cut.svg"] = '<svg width="10" height="10"><path d="M0 0 L',
      ["odd.svg"] = '<svg viewBox="0 0 10 10"><path d="M1e9 nan L5 5 Q A 1 Z z z"/><rect width="-5" height="x"/><g transform="rotate(nan) bogus(1"><circle r="5"/></g></svg>' } do
    local f = io.open(name, "w") f:write(text) f:close()
    local bad = loadShape(name) if bad then shape(bad, 0, 0, 50, 50) shape(bad, 0, 0, 0, 0) shape(bad, 0/0, 0, 1e9, -5) end
  end

  -- tables
  local f = io.open("scores.csv", "w")
  f:write('name,score,note\r\nAda,12,"likes ""quotes"", and commas"\nGrace,7.5,\n\n"Multi\nline",3,x\n') f:close()
  local t = loadTable("scores.csv", "header")
  assert(t:getRowCount() == 3 and t:getColumnCount() == 3, "3 rows, 3 columns: " .. t:getRowCount())
  assert(t:getString(0, "name") == "Ada" and t:getInt(0, "score") == 12 and t:getString(0, 2) == 'likes "quotes", and commas')
  assert(t:getFloat(1, "score") == 7.5 and t:getInt(1, 1) == 7 and t:getString(1, "note") == "" and t:getString(2, 0) == "Multi\nline")
  assert(t:getColumnTitles()[2] == "score")
  local names = {} for row in t:rows() do names[#names + 1] = row:getString("name") end assert(#names == 3 and names[2] == "Grace")
  assert(not pcall(t.getString, t, 0, "nope") and not pcall(t.getString, t, 99, 0), "unknown column and row are errors")
  local row = t:addRow() row:setString("name", "Lin") row:setInt("score", 40.9) t:setFloat(3, "note", 1.5)
  assert(t:getRowCount() == 4 and t:getInt(3, "score") == 40)
  assert(saveTable(t, "out.csv")) local back = loadTable("out.csv", "header")
  assert(back:getRowCount() == 4 and back:getString(0, "note") == 'likes "quotes", and commas' and back:getString(3, "name") == "Lin" and back:getString(2, 0) == "Multi\nline", "round trip")
  local plain = loadTable("scores.csv") assert(plain:getRowCount() == 4 and plain:getString(0, 0) == "name", "without header")
  f = io.open("t.tsv", "w") f:write("a\tb\n1\t2\n") f:close() local tsv = loadTable("t.tsv", "header") assert(tsv:getInt(0, "b") == 2, "tsv")
  local made = createTable("x", "y") made:addRow():setInt("x", 5) assert(saveTable(made, "made.csv") and loadTable("made.csv", "header"):getInt(0, "x") == 5)
  assert(loadTable("missing.csv") == nil) assert(not pcall(saveTable, {}, "x.csv"))
  print("ok") exit()
end
