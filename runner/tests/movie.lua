-- Movie through ffmpeg: frames, time, jump
-- stdout: ok
-- timeout: 40
-- ffmpeg can be slow to start on a busy machine, so each step waits for the
-- picture it expects (for a while) instead of a fixed number of frames.
local m
function setup() size(100, 100) m = Movie(os.getenv("LUAMODE_TESTS") .. "/assets/redblue.mp4") end
local phase, waited, got = 1, 0, false
function draw()
  if m:available() then m:read() got = true end
  image(m, 0, 0, 100, 100)
  waited = waited + 1
  local r, g, b = get(50, 50)
  if phase == 1 then
    -- the first frame shows before play()
    if got and r > 200 and b < 60 then
      assert(math.abs(m:duration() - 2) < 0.2 and m.width == 64, "duration and size")
      m:jump(1.5) m:play()
      phase, waited = 2, 0
    else
      assert(waited < 900, "first frame shows before play: " .. r .. "," .. g .. "," .. b)
    end
  elseif phase == 2 then
    if b > 200 and r < 60 then print("ok") exit() end
    assert(waited < 900, "after jump: " .. r .. "," .. g .. "," .. b)
  end
end
