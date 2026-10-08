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

-- ── More math ─────────────────────────────────────────────────────────────
function bezierPoint(a, b, c, d, t)
  local u = 1 - t
  return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
end
function bezierTangent(a, b, c, d, t)
  local u = 1 - t
  return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
end
function curvePoint(a, b, c, d, t)
  local t2, t3 = t * t, t * t * t
  return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
end
function curveTangent(a, b, c, d, t)
  local t2 = t * t
  return 0.5 * ((-a + c) + 2 * (2 * a - 5 * b + 4 * c - d) * t + 3 * (-a + 3 * b - 3 * c + d) * t2)
end

-- ── Date and time (local) ─────────────────────────────────────────────────
function year()   return os.date("*t").year  end
function month()  return os.date("*t").month end
function day()    return os.date("*t").day   end
function hour()   return os.date("*t").hour  end
function minute() return os.date("*t").min   end
function second() return os.date("*t").sec   end

-- ── Strings and files ─────────────────────────────────────────────────────
function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function join(list, sep) return table.concat(list, sep or "") end
-- split("a,b,c", ",") -> {"a", "b", "c"}; the separator is plain text
function split(s, sep)
  local out, from = {}, 1
  s, sep = tostring(s), tostring(sep or " ")
  if sep == "" then
    for i = 1, #s do out[i] = s:sub(i, i) end
    return out
  end
  while true do
    local a, b = s:find(sep, from, true)
    if not a then out[#out + 1] = s:sub(from) break end
    out[#out + 1] = s:sub(from, a - 1)
    from = b + 1
  end
  return out
end
-- nf(7, 3) -> "007"; nf(3.14159, 1, 2) -> "3.14"
function nf(n, left, right)
  if type(n) ~= "number" then error("nf() expects a number", 2) end
  local neg = n < 0
  local s
  if right then s = string.format("%." .. right .. "f", math.abs(n))
  else s = tostring(math.floor(math.abs(n) + 0.5)) end
  local whole = s:match("^%d+")
  if left and #whole < left then s = string.rep("0", left - #whole) .. s end
  return (neg and "-" or "") .. s
end
-- loadStrings("notes.txt") -> a list of lines, or nil if the file can't be read
function loadStrings(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("loadStrings: could not open " .. tostring(path) .. "\n")
    return nil
  end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = (line:gsub("\r$", "")) end
  f:close()
  return lines
end
function saveStrings(path, lines)
  local f, why = io.open(path, "w")
  if not f then
    io.stderr:write("saveStrings: could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n")
    return false
  end
  for _, line in ipairs(lines) do f:write(tostring(line), "\n") end
  f:close()
  return true
end
function save(name) saveFrame(name or "screen.png") end

-- ── Numbers as text ───────────────────────────────────────────────────────
-- hex(255) -> "FF", hex(255, 6) -> "0000FF", unhex("FF") -> 255
function hex(n, digits)
  if math.type(n) ~= "integer" then n = math.floor(n) end
  local s = string.format("%X", n & 0xFFFFFFFF)
  if digits and #s < digits then s = string.rep("0", digits - #s) .. s end
  if digits and #s > digits then s = s:sub(-digits) end
  return s
end
function unhex(s) return tonumber(tostring(s), 16) or 0 end
function binary(n, digits)
  if math.type(n) ~= "integer" then n = math.floor(n) end
  n = n & 0xFFFFFFFF
  local s = ""
  repeat s = (n & 1) .. s n = n >> 1 until n == 0
  if digits and #s < digits then s = string.rep("0", digits - #s) .. s end
  if digits and #s > digits then s = s:sub(-digits) end
  return s
end
function unbinary(s) return tonumber(tostring(s), 2) or 0 end

-- printArray({ "a", "b" }) prints "[1] a" and "[2] b", one per line
function printArray(list)
  if type(list) ~= "table" then return print(list) end
  for i, v in ipairs(list) do print("[" .. i .. "] " .. tostring(v)) end
end

-- ── JSON ──────────────────────────────────────────────────────────────────
-- parseJSON('{"a": [1, 2]}') -> { a = { 1, 2 } }      toJSON(value) -> text
-- loadJSON("data.json") -> value, or nil if it can't be read or isn't JSON
-- saveJSON("data.json", value)
-- JSON null becomes nil. A table with only 1..n keys is written as a list,
-- any other table as an object; an empty table is written as [].
do
  local function decode_error(text, pos, what)
    local line = 1
    for _ in text:sub(1, pos):gmatch("\n") do line = line + 1 end
    error("JSON line " .. line .. ": " .. what, 0)
  end
  local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
  local decode_value

  local function skip(text, pos)
    return text:find("%S", pos) or #text + 1
  end
  local function decode_string(text, pos)
    local out, i = {}, pos + 1
    while true do
      local a = text:find('["\\]', i)
      if not a then decode_error(text, pos, "text that never ends") end
      out[#out + 1] = text:sub(i, a - 1)
      if text:sub(a, a) == '"' then return table.concat(out), a + 1 end
      local e = text:sub(a + 1, a + 1)
      if e == "u" then
        local code = tonumber(text:sub(a + 2, a + 5), 16)
        if not code then decode_error(text, a, "bad \\u escape") end
        i = a + 6
        -- two \u escapes can make one character
        if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == "\\u" then
          local low = tonumber(text:sub(i + 2, i + 5), 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8.char(code)
      elseif escapes[e] then
        out[#out + 1] = escapes[e]
        i = a + 2
      else
        decode_error(text, a, "bad escape \\" .. e)
      end
    end
  end
  local function decode_container(text, pos, depth, close, with_keys)
    if depth > 200 then decode_error(text, pos, "nested too deeply") end
    local out, i, n = {}, skip(text, pos + 1), 0
    if text:sub(i, i) == close then return out, i + 1 end
    while true do
      local key
      if with_keys then
        if text:sub(i, i) ~= '"' then decode_error(text, i, "expected a name in quotes") end
        key, i = decode_string(text, i)
        i = skip(text, i)
        if text:sub(i, i) ~= ":" then decode_error(text, i, "expected ':'") end
        i = skip(text, i + 1)
      end
      local value
      value, i = decode_value(text, i, depth + 1)
      if with_keys then out[key] = value else n = n + 1 out[n] = value end
      i = skip(text, i)
      local c = text:sub(i, i)
      if c == close then return out, i + 1 end
      if c ~= "," then decode_error(text, i, "expected ',' or '" .. close .. "'") end
      i = skip(text, i + 1)
    end
  end
  decode_value = function(text, pos, depth)
    pos = skip(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then return decode_container(text, pos, depth, "}", true) end
    if c == "[" then return decode_container(text, pos, depth, "]", false) end
    if c == '"' then return decode_string(text, pos) end
    if text:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    if text:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    if text:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
    local num = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    local value = num and tonumber(num)
    if not value then decode_error(text, pos, c == "" and "the text ends too soon" or "unexpected '" .. c .. "'") end
    return value, pos + #num
  end

  -- parseJSON(text) -> value. A mistake in the text is an error that says which line.
  function parseJSON(text)
    if type(text) ~= "string" then error("parseJSON() expects text", 2) end
    local ok, value, pos = pcall(decode_value, text, 1, 0)
    if not ok then error(value, 2) end
    if skip(text, pos) <= #text then error("JSON: extra text after the value", 2) end
    return value
  end

  local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
      local short = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
      return short[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  local function encode(v, indent, seen, out)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"   -- JSON has no NaN or infinity
      elseif math.type(v) == "integer" then out[#out + 1] = tostring(v)
      else out[#out + 1] = string.format("%.14g", v) end
    elseif t == "string" then out[#out + 1] = quote(v)
    elseif t == "table" then
      if seen[v] then error("toJSON(): a table contains itself", 0) end
      seen[v] = true
      local n = #v
      local list = true
      for k in pairs(v) do
        if math.type(k) ~= "integer" or k < 1 or k > n then list = false break end
      end
      local pad, inner = "\n" .. string.rep("  ", indent), "\n" .. string.rep("  ", indent + 1)
      if list then
        if n == 0 then out[#out + 1] = "[]" else
          out[#out + 1] = "["
          for i = 1, n do
            out[#out + 1] = (i > 1 and "," or "") .. inner
            encode(v[i], indent + 1, seen, out)
          end
          out[#out + 1] = pad .. "]"
        end
      else
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)                      -- the same table always gives the same text
        local by_name = {}
        for k, val in pairs(v) do by_name[tostring(k)] = val end
        out[#out + 1] = "{"
        for i, k in ipairs(keys) do
          out[#out + 1] = (i > 1 and "," or "") .. inner .. quote(k) .. ": "
          encode(by_name[k], indent + 1, seen, out)
        end
        out[#out + 1] = pad .. "}"
      end
      seen[v] = nil
    else
      error("toJSON(): can't write a " .. t, 0)
    end
  end
  function toJSON(value)
    local out = {}
    local ok, why = pcall(encode, value, 0, {}, out)
    if not ok then error(why, 2) end
    return table.concat(out)
  end

  function loadJSON(path)
    local f = io.open(path, "rb")
    if not f then
      io.stderr:write("loadJSON: could not open " .. tostring(path) .. "\n")
      return nil
    end
    local text = f:read("a")
    f:close()
    text = text:gsub("^\xEF\xBB\xBF", "")
    local ok, value = pcall(parseJSON, text)
    if not ok then
      io.stderr:write("loadJSON: " .. tostring(path) .. ": " .. tostring(value) .. "\n")
      return nil
    end
    return value
  end
  function saveJSON(path, value)
    local text = toJSON(value)
    local f, why = io.open(path, "w")
    if not f then
      io.stderr:write("saveJSON: could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n")
      return false
    end
    f:write(text, "\n")
    f:close()
    return true
  end
end

-- ── PVector ───────────────────────────────────────────────────────────────
-- v = createVector(3, 4)   v:add(w)   v:mag()   local sum = a + b
-- Methods change the vector and return it, so they chain. The operators
-- (+ - * / and unary -) make a new vector.
PVector = {}
PVector.__index = PVector
local function vec(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, PVector) end
local function isvec(v) return getmetatable(v) == PVector end
local function parts(a, b, c)
  if isvec(a) then return a.x, a.y, a.z end
  return a or 0, b or 0, c or 0
end
function createVector(x, y, z) return vec(x, y, z) end
PVector.new = vec
function PVector.fromAngle(a) return vec(math.cos(a), math.sin(a), 0) end
function PVector.random2D() return PVector.fromAngle(random(TWO_PI)) end
function PVector:copy() return vec(self.x, self.y, self.z) end
function PVector:set(a, b, c) self.x, self.y, self.z = parts(a, b, c) return self end
function PVector:mag() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function PVector:magSq() return self.x * self.x + self.y * self.y + self.z * self.z end
-- pos:add(vel) changes pos, as in Processing. For a new vector use the
-- operators: local sum = a + b
function PVector:add(a, b, c) local x, y, z = parts(a, b, c) self.x, self.y, self.z = self.x + x, self.y + y, self.z + z return self end
function PVector:sub(a, b, c) local x, y, z = parts(a, b, c) self.x, self.y, self.z = self.x - x, self.y - y, self.z - z return self end
function PVector:mult(n) self.x, self.y, self.z = self.x * n, self.y * n, self.z * n return self end
function PVector:div(n)  self.x, self.y, self.z = self.x / n, self.y / n, self.z / n return self end
function PVector:dot(v)  return self.x * v.x + self.y * v.y + self.z * v.z end
function PVector:cross(v)
  return vec(self.y * v.z - self.z * v.y, self.z * v.x - self.x * v.z, self.x * v.y - self.y * v.x)
end
function PVector:dist(v)
  local dx, dy, dz = self.x - v.x, self.y - v.y, self.z - v.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end
function PVector:normalize()
  local m = self:mag()
  if m > 0 then self:div(m) end
  return self
end
function PVector:setMag(n) return self:normalize():mult(n) end
function PVector:limit(n)
  if self:magSq() > n * n then self:setMag(n) end
  return self
end
function PVector:heading() return math.atan(self.y, self.x) end
function PVector:rotate(a)
  local c, s = math.cos(a), math.sin(a)
  self.x, self.y = self.x * c - self.y * s, self.x * s + self.y * c
  return self
end
function PVector:lerp(v, t)
  self.x, self.y, self.z = self.x + (v.x - self.x) * t, self.y + (v.y - self.y) * t, self.z + (v.z - self.z) * t
  return self
end
function PVector.angleBetween(a, b)
  local m = a:mag() * b:mag()
  if m == 0 then return 0 end
  return math.acos(math.max(-1, math.min(1, a:dot(b) / m)))
end
PVector.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
PVector.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
PVector.__mul = function(a, b)
  if type(a) == "number" then return vec(b.x * a, b.y * a, b.z * a) end
  return vec(a.x * b, a.y * b, a.z * b)
end
PVector.__div = function(a, n) return vec(a.x / n, a.y / n, a.z / n) end
PVector.__unm = function(a) return vec(-a.x, -a.y, -a.z) end
PVector.__eq  = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
PVector.__tostring = function(a) return "[ " .. a.x .. ", " .. a.y .. ", " .. a.z .. " ]" end

-- ── createGraphics ────────────────────────────────────────────────────────
-- local pg = createGraphics(200, 100)
-- pg:beginDraw()  pg:background(0)  pg:ellipse(50, 50, 40, 40)  pg:endDraw()
-- image(pg, 10, 10)
-- Between beginDraw and endDraw every drawing function draws on the layer,
-- so pg:ellipse(...) and plain ellipse(...) do the same thing there. A layer
-- starts out transparent. Make layers once, in setup().
do
  local create, begin, finish, show = __createGraphics, __beginGraphics, __endGraphics, __imageGraphics
  __createGraphics, __beginGraphics, __endGraphics, __imageGraphics = nil, nil, nil, nil
  local Layer = {}
  local forwards = {}   -- pg:name(...) -> name(...), made once per name
  Layer.__index = function(_, name)
    local own = rawget(Layer, name)
    if own then return own end
    local f = forwards[name]
    if not f then
      local target = _G[name]
      if type(target) ~= "function" then return nil end
      f = function(_, ...) return _G[name](...) end
      forwards[name] = f
    end
    return f
  end
  function Layer:beginDraw()
    if not begin(self.id) then error("beginDraw(): this layer is already being drawn to", 2) end
  end
  function Layer:endDraw() finish() end
  Layer.__tostring = function(l) return "layer " .. l.width .. "x" .. l.height end

  function createGraphics(w, h)
    local id, rw, rh = create(w, h)
    if id == 0 then error("createGraphics(): could not make the layer (too many, or too big)", 2) end
    return setmetatable({ id = id, width = rw, height = rh }, Layer)
  end

  local drawImage = image
  function image(img, ...)
    if getmetatable(img) == Layer then return show(img.id, ...) end
    return drawImage(img, ...)
  end
end
