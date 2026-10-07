-- windowResizable() is accepted with true, false and no argument
-- stdout: ok
function setup()
  size(120, 90)
  windowResizable(false)
  windowResizable()
  windowResizable(true)
  print("ok")
end
function draw()
  if frameCount == 3 then exit() end
end
