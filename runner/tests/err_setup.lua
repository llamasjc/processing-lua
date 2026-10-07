-- rc: 1
-- stderr: err_setup.lua:5: attempt to perform arithmetic on a nil value (global 'nothing')
-- stderr-lines: 1
function setup()
  local x = nothing + 1
end
function draw() print("should never draw") end
