-- rc: 1
-- env: LUAMODE_MEMORY_MB=64
-- stderr: not enough memory
-- A loop that allocates forever ends in a Lua error, not in swap.
function setup()
  local t = {}
  while true do t[#t + 1] = string.rep("x", 1024) .. #t end
end
