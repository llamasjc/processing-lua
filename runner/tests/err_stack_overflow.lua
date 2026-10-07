-- rc: 1
-- stderr: err_stack_overflow.lua:
-- stderr: stack overflow
local function f(n) return 1 + f(n + 1) end
function setup() f(1) end
