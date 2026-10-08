-- sound files and oscillators (the test machine has a silent sound card, or none)
-- stdout: ok
-- stderr: missing.wav
local assets = os.getenv("LUAMODE_TESTS") .. "/assets/"
local function near(a, b, what) assert(math.abs(a - b) < 0.02, what .. ": " .. tostring(a)) end
function setup() size(60, 40) noLoop() end
function draw()
  local s = loadSound(assets .. "tone.wav")
  assert(s, "loads a WAV") near(s:duration(), 1.0, "one second long")
  assert(not s:isPlaying() and s:position() == 0, "silent until played") assert(tostring(s):find("1.00 seconds"))
  -- controls can be set before and while playing, and chain
  assert(s:amp(0.5):pan(-1):rate(2) == s)
  s:jump(0.5) near(s:position(), 0.5, "jump") s:jump(99) near(s:position(), 1.0, "jump stops at the end") s:jump(-5) assert(s:position() == 0)
  s:play() s:pause() s:play() s:stop() assert(not s:isPlaying() and s:position() == 0, "stop goes back to the start")
  s:loop() s:stop() s:play()
  -- with a sound card it plays to the end and stops by itself; without one it never starts
  local t0 = os.clock()
  while s:isPlaying() and os.clock() - t0 < 3 do end
  assert(not s:isPlaying(), "a sound that isn't looping ends")
  -- bad values
  assert(not pcall(s.amp, s, "loud") and not pcall(s.rate, s))
  s:amp(0/0) s:amp(-3) s:amp(1e9) s:pan(0/0) s:pan(50) s:rate(0) s:rate(0/0) s:rate(1e9) s:jump(0/0) s:play() s:stop()
  -- other formats are told apart from garbage
  assert(loadSound("missing.wav") == nil)
  local f = io.open("junk.wav", "w") f:write("this is not sound") f:close() assert(loadSound("junk.wav") == nil)
  f = io.open("empty.wav", "w") f:close() assert(loadSound("empty.wav") == nil)

  -- oscillators
  for _, make in ipairs { SinOsc, SqrOsc, SawOsc, TriOsc, WhiteNoise } do
    local o = make()
    assert(not o:isPlaying(), "silent until play()")
    assert(o:freq(220):amp(0.2):pan(1) == o)
    o:play() o:freq(880) o:freq(0) o:freq(1e9) o:freq(0/0) o:amp(0) o:stop() assert(not o:isPlaying())
    assert(not pcall(o.freq, o, "high"))
  end
  -- far too many: an error that says so, not a crash
  local ok, why = pcall(function() for i = 1, 200 do SinOsc() end end)
  assert(not ok and tostring(why):find("too many"), tostring(why))
  assert(loadSound(assets .. "tone.wav") == nil, "no room left for a file either")
  print("ok") exit()
end
