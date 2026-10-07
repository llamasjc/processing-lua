-- rc: 1
-- stderr: err_bad_argument.lua:6: bad argument #3 to ellipse(): expected a number, got nil
-- stderr-lines: 1
function setup() size(100, 100) end
function draw()
  ellipse(10, 20)
end
