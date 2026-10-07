-- stdout: ok
-- a byte order mark and a Latin-1 comment: café
local s = "é"
function setup() print("ok") exit() end
