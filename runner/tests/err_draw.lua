-- rc: 1
-- stderr: err_draw.lua:8: attempt to call a nil value (global 'elipse')
-- stderr-lines: 1
-- The first error stops the sketch: one line, not sixty a second.
function setup() size(100, 100) end
function draw()
  background(0)
  elipse(10, 10, 5, 5)
end
