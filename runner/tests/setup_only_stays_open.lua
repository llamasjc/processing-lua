-- rc: 124
-- timeout: 10
-- (long enough for libprocessing to start on a slow machine; it only has to stay open)
-- stdout: hello
-- stderr-lines: 0
function setup() size(200, 200) background(255) print("hello") end
