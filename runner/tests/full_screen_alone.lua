-- fullScreen() without a screen from the IDE: says so, keeps a window
-- stdout: ok 100x100
-- stderr: fullScreen() only works
function setup() fullScreen() end
function draw() print("ok " .. width .. "x" .. height) exit() end
