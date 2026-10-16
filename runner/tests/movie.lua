-- Movie through ffmpeg: frames, time, jump
-- stdout: ok
-- timeout: 20
local m
function setup() size(100, 100) m = Movie(os.getenv("LUAMODE_TESTS") .. "/assets/redblue.mp4") end
local step = 0
function draw()
  if m:available() then m:read() end
  image(m, 0, 0, 100, 100)
  step = step + 1
  if step == 20 then
    local r, g, b = get(50, 50)
    assert(r > 200 and b < 60, "first frame shows before play: " .. r .. "," .. g .. "," .. b)
    assert(math.abs(m:duration() - 2) < 0.2 and m.width == 64, "duration and size")
    m:jump(1.5) m:play()
  end
  if step == 60 then
    local r, g, b = get(50, 50)
    assert(b > 200 and r < 60, "after jump: " .. r .. "," .. g .. "," .. b)
    print("ok") exit()
  end
end
