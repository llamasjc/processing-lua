-- Runs once before the sketch. Everything here is plain Lua on purpose: the
-- math helpers keep Lua's own number rules (integers stay integers, full
-- double precision) and errors point at the line in the sketch that called
-- them.

-- ── Math ──────────────────────────────────────────────────────────────────
abs, floor, ceil, sqrt, exp   = math.abs, math.floor, math.ceil, math.sqrt, math.exp
sin, cos, tan                 = math.sin, math.cos, math.tan
asin, acos, atan              = math.asin, math.acos, math.atan
min, max, log                 = math.min, math.max, math.log
degrees, radians              = math.deg, math.rad

function atan2(y, x) return math.atan(y, x) end
function pow(b, e)   return b ^ e end
function sq(v)       return v * v end
function round(v)    return math.floor(v + 0.5) end

-- int("42"), int(3.9) -> 3, int(-3.9) -> -3, like Processing
function int(v)
  if type(v) == "string" then v = tonumber(v) or 0 end
  if type(v) == "boolean" then return v and 1 or 0 end
  if type(v) ~= "number" then error("int() expects a number or a string", 2) end
  if v ~= v or v == math.huge or v == -math.huge then return 0 end
  return v >= 0 and math.floor(v) or math.ceil(v)
end

function str(v) return tostring(v) end

function map(v, a1, b1, a2, b2) return a2 + (v - a1) / (b1 - a1) * (b2 - a2) end
function norm(v, a, b)          return (v - a) / (b - a) end
function lerp(a, b, t)          return a + (b - a) * t end

-- written out by hand so constrain(v, 10, 0) can't blow up
function constrain(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

function mag(x, y) return math.sqrt(x * x + y * y) end

-- ── Console ───────────────────────────────────────────────────────────────
-- print() is replaced by the runner (flushes every line). io.write goes
-- through C stdio, which holds output back when it isn't a terminal.
pcall(function() io.stdout:setvbuf("line") end)
println = print

-- ── frameRate ─────────────────────────────────────────────────────────────
-- In Processing frameRate is both a number you read and a function you call.
-- A Lua global can't be both, so the global stays a plain number and numbers
-- get a __call that only accepts being called on that exact value:
--   frameRate(30)   sets the target
--   frameRate       reads the current rate
-- Calling any other number is still the usual error.
do
  local set = __luamode_set_frame_rate
  __luamode_set_frame_rate = nil
  debug.setmetatable(0, {
    __call = function(self, fps)
      if not rawequal(self, frameRate) then
        error("attempt to call a number value", 2)
      end
      if fps == nil then return self end
      if type(fps) ~= "number" then
        error("frameRate() expects a number, got " .. type(fps), 2)
      end
      frameRate = set(fps)
    end,
  })
end
