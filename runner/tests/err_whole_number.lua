-- rc: 1
-- stderr: err_whole_number.lua:4: bad argument #1 to rectMode(): expected a whole number
-- stderr-lines: 1
function setup() rectMode(1e30) end
