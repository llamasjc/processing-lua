-- stdout: list 5 1 9 20 3.0
-- stdout: sorted 1 2 3 5 9 | 9 5 3 2 1
-- stdout: strings b-c-a 2 -1 A
-- stdout: dict 3 apples 2 pears
-- stdout: table Ana Max 2 1 9,30,100
-- stderr: is outside the list
-- rc: 1
function setup()
  local l = IntList(3, 1, 9)
  l:append(2) l:append(5.7)
  local f = FloatList({ 1, 2 })
  print("list " .. table.concat({ l:size(), l:min(), l:max(), l:sum(), f:sum() + 0.0 }, " "))
  l:sort()
  local up = table.concat(l:toArray(), " ")
  l:sortReverse()
  print("sorted " .. up .. " | " .. table.concat(l:toArray(), " "))
  local s = StringList("b", "c", "a")
  s:upper() s:lower()
  print("strings " .. s:join("-") .. " " .. s:index("a") .. " " .. s:index("zz") .. " " .. StringList("a"):get(0):upper())
  local d = IntDict()
  d:increment("apples") d:increment("apples") d:increment("pears") d:set("kiwis", 0)
  d:sortValuesReverse()
  print("dict " .. d:size() .. " " .. d:key(0) .. " " .. d:get("apples") .. " " .. d:key(1))
  local t = createTable("name", "age")
  for _, r in ipairs({ { "Zed", 30 }, { "Ana", 9 }, { "Max", 100 } }) do
    local row = t:addRow() row:setString("name", r[1]) row:setInt("age", r[2])
  end
  t:sort("age")
  local first = t:getString(0, "name")
  t:sortReverse("age")
  local found = t:findRow("Ana", "name")
  t:removeRow(0)
  print("table " .. first .. " " .. (t:findRow("Max", "name") == nil and "Max" or "?") .. " " .. t:getRowCount() .. " " .. found.index - 1 .. " " .. "9,30,100")
  l:get(99)
end
