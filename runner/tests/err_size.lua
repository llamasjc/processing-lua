-- rc: 1
-- stderr: err_size.lua:4: size() needs a width and height of at least 1
-- stderr-lines: 1
function setup() size(0, -5) end
