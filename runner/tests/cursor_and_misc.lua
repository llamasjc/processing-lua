-- stdout: ok
function setup()
  size(80, 80)
  windowTitle("misc") smooth() noSmooth() noCursor() cursor()
  assert(millis() >= 0)
  delay(5) delay(-5) delay(0/0) delay("3")
  assert(type(debug.traceback()) == "string", "debug library is there")
  assert(key == "" and keyCode == 0 and mouseButton == 0)
  assert(mousePressed == false and keyPressed == false)
  print("ok") exit()
end
