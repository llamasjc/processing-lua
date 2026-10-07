-- stdout: ok
function setup()
  size(100, 100)
  assert(frameRate == 60, "default target")
  frameRate(30)
  assert(frameRate == 30, "frameRate(30) shows up at once: " .. tostring(frameRate))
  assert(frameRate() == 30, "frameRate() reads")
  assert(frameRate + 1 == 31 and frameRate < 31, "still an ordinary number")
  assert(string.format("%d", floor(frameRate)) == "30")
  frameRate(-5)   assert(frameRate >= 1, "negative is clamped")
  frameRate(1e9)  assert(frameRate <= 1000, "huge is clamped")
  frameRate(0/0)  assert(frameRate == frameRate, "NaN doesn't stick")
  setFrameRate(120)
  assert(frameRate == 120)
  local n = 5
  local ok, err = pcall(function() return n(3) end)
  assert(not ok and tostring(err):find("attempt to call a number value"), "calling another number still fails: " .. tostring(err))
  local ok2, err2 = pcall(function() frameRate("fast") end)
  assert(not ok2 and tostring(err2):find("expects a number"), tostring(err2))
end
function draw()
  if frameCount == 3 then frameRate(200) end     -- changing it mid-sketch works too
  if frameCount == 20 then
    assert(frameRate > 1 and frameRate <= 1000, "measured rate is sane: " .. frameRate)
    print("ok") exit()
  end
end
