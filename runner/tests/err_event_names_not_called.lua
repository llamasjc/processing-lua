-- stdout: ok
-- Globals that happen to share a callback's name but aren't functions are left alone.
mouseMoved = 5
keyTyped = "x"
draw = nil
function setup() print("ok") exit() end
