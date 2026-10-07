-- stdout: a	1	true	nil
-- stdout: 2.5
-- stdout: last line 20000
-- stdout: written with io.write
function setup()
  print("a", 1, true, nil)
  println(2.5)
  print()
  print("bytes \xff ok")
  io.write("written with io.write\n")
  for i = 1, 20000 do print("last line " .. i) end
  exit()
end
