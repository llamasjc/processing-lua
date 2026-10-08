-- fullScreen() with a screen from the IDE: canvas and window take its size
-- stdout: ok 300x200 300x200
-- env: PROCESSING_DISPLAY=300,200,0,0
function setup() fullScreen() print("in setup", width, height) end
function draw()
  if frameCount == 3 then
    background(255) local r = get(299, 199)
    print("ok " .. width .. "x" .. height .. " " .. displayWidth .. "x" .. displayHeight) assert(r == 255) exit()
  end
end
