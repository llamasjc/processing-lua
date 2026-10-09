-- stdout: inside true outside false
function setup()
  size(200, 100)
  background(255)
  fill(0)
  textSize(12)
  textAlign(LEFT, TOP)
  text("a long sentence that has to wrap over several lines in this box", 10, 10, 60, 80)
  local ink, outside = false, false
  for y = 10, 90 do for x = 10, 70 do if get(x, y) < 128 then ink = true end end end
  for y = 0, 99 do for x = 80, 199 do if get(x, y) < 128 then outside = true end end end
  print("inside " .. tostring(ink) .. " outside " .. tostring(outside))
  exit()
end
