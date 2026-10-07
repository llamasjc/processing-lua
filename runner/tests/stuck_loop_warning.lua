-- rc: 124
-- timeout: 14
-- stderr: press Stop
-- stderr-lines: 1
-- A sketch that never finishes a frame gets told so once.
function setup()
  local n = 0
  while true do n = n + 1 end
end
