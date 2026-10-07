-- stdout: ok
-- A typo in size() gets clamped instead of asking for terabytes.
function setup()
  size(1e12, 3)
  assert(width <= 8192 and height == 3, width .. "x" .. height)
  size(123.6, 77.2)
  assert(width == 124 and height == 77)
  print("ok") exit()
end
