-- rc: 1
-- stderr: err_nested.lua:5: bad argument #1 to rect(): expected a number, got table
-- stderr-lines: 1
-- The line reported is where our function was called, however deep.
local function inner() rect({}, 1, 2, 3) end
local function outer() inner() end
function draw() outer() end
