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

-- ── More of Processing's constants ────────────────────────────────────────
-- Processing's own values. X, Y and Z are left out: they would clash with a
-- sketch's own variables. cursor(HAND) and the other kinds change the
-- cursor's look (WAIT is the arrow on the default renderer).
ARGB, ALPHA = 2, 4
ARROW, CROSS, TEXT, WAIT, HAND, MOVE = 0, 1, 2, 3, 12, 13
VERTEX, BEZIER_VERTEX, QUADRATIC_VERTEX, CURVE_VERTEX, BREAK = 0, 1, 2, 3, 4
QUAD_BEZIER_VERTEX = 2
NEAREST_NEIGHBOR, BILINEAR, BICUBIC = 0, 1, 2
-- the blend modes blend() has besides the blendMode() ones
OVERLAY, HARD_LIGHT, SOFT_LIGHT, DODGE, BURN = 512, 1024, 2048, 4096, 8192
DEG_TO_RAD, RAD_TO_DEG, THIRD_PI = math.pi / 180, 180 / math.pi, math.pi / 3
EPSILON = 0.0001
MAX_FLOAT, MIN_FLOAT = 3.4028234663852886e38, -3.4028234663852886e38
MAX_INT, MIN_INT = 2147483647, -2147483648
TIFF, TARGA, JPEG, GIF = 0, 1, 2, 3
PORTRAIT, LANDSCAPE = 1, 2
OTHER, WINDOWS, MACOS, MACOSX, LINUX = 0, 1, 2, 2, 3
PROJECTION, MODELVIEW, ORTHOGRAPHIC, PERSPECTIVE = 0, 1, 2, 3
AMBIENT, DIRECTIONAL, SPOT = 0, 1, 3
DIAMETER = 3
CUSTOM, MODEL, SHAPE, SPAN = 0, 4, 5, 0
PATH = 21
LINE_STRIP, LINE_LOOP = 50, 51
ENABLE_NATIVE_FONTS, DISABLE_NATIVE_FONTS = 1, -1
ENABLE_BUFFER_READING, DISABLE_BUFFER_READING = 10, -10
DISABLE_KEY_REPEAT, ENABLE_KEY_REPEAT = 11, -11
HINT_COUNT = 13
CHATTER, COMPLAINT, PROBLEM = 0, 1, 2
WHITESPACE = " \t\n\r\f\u{00A0}"
-- renderer names; size(w, h, P3D) is what changes anything
JAVA2D = "processing.awt.PGraphicsJava2D"
FX2D = "processing.javafx.PGraphicsFX2D"
WEBGPU = "processing.webgpu.PGraphicsWebGPU"
DXF = "processing.dxf.RawDXF"
OPENGL = P3D
-- PShape.GROUP, PShape.PRIMITIVE, PShape.PATH, PShape.GEOMETRY for getFamily()
PShape = { GROUP = 0, PRIMITIVE = 101, PATH = 102, GEOMETRY = 103 }

-- size(w, h, P3D) notes the renderer for is2D() / is3D()
function is3D() return rawget(_G, "__renderer") == P3D end
function is2D() return not is3D() end
function orientation() end
do
  local looping, loopOn, loopOff = true, loop, noLoop
  function loop() looping = true return loopOn() end
  function noLoop() looping = false return loopOff() end
  function isLooping() return looping end
end
-- attribColor("name", c): a color attribute, as four numbers 0..1
function attribColor(name, c) attrib(name, red(c) / 255, green(c) / 255, blue(c) / 255, alpha(c) / 255) end

-- ── More math ─────────────────────────────────────────────────────────────
function bezierPoint(a, b, c, d, t)
  local u = 1 - t
  return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
end
function bezierTangent(a, b, c, d, t)
  local u = 1 - t
  return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
end
function curvePoint(a, b, c, d, t) return __curve(a, b, c, d, t, 0) end
function curveTangent(a, b, c, d, t) return __curve(a, b, c, d, t, 1) end

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
-- nfc(1234567) -> "1,234,567"; nfc(1234.5, 2) -> "1,234.50"
function nfc(n, right)
  if type(n) ~= "number" then error("nfc() expects a number", 2) end
  local s = right and string.format("%." .. right .. "f", math.abs(n)) or tostring(math.floor(math.abs(n) + 0.5))
  local whole, rest = s:match("^(%d+)(.*)$")
  whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. whole .. rest
end
-- nfs: like nf, with a space where a minus would go, so columns line up
function nfs(n, left, right)
  local s = nf(n, left, right)
  if n < 0 then return s end
  return " " .. s
end
-- nfp: like nf, with a + on positive numbers
function nfp(n, left, right)
  local s = nf(n, left, right)
  if n < 0 then return s end
  return "+" .. s
end
-- splitTokens("a, b  c", ", ") -> {"a", "b", "c"}: split on any of the characters, no empty pieces
function splitTokens(s, delims)
  delims = delims or " \t\n\r\f"
  local out = {}
  local class = "[^" .. delims:gsub("[%]%^%-%%]", "%%%0") .. "]+"
  for piece in tostring(s):gmatch(class) do out[#out + 1] = piece end
  return out
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
      -- IntList, StringDict and the like are written as their values
      local mt = getmetatable(v)
      if mt and type(mt.__name) == "string" and (mt.__name:match("List$") or mt.__name:match("Dict$")) and v.toJSON then
        v = v:toJSON()
      end
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
  -- Processing's names: an object (a table with keys) or an array (a list)
  local function isArray(t) return type(t) == "table" and (#t > 0 or next(t) == nil) end
  function loadJSONObject(path) local v = loadJSON(path) if type(v) == "table" and not isArray(v) then return v end return nil end
  function loadJSONArray(path) local v = loadJSON(path) if isArray(v) then return v end return nil end
  function parseJSONObject(text) local ok, v = pcall(parseJSON, text) if ok and type(v) == "table" and not isArray(v) then return v end return nil end
  function parseJSONArray(text) local ok, v = pcall(parseJSON, text) if ok and isArray(v) then return v end return nil end
  function saveJSONObject(value, path) return saveJSON(path, value) end
  function saveJSONArray(value, path) return saveJSON(path, value) end
end

-- ── bytes and conversions ─────────────────────────────────────────────────
-- loadBytes("file") -> a list of numbers 0..255 (nil if it can't be read)
function loadBytes(path)
  local f = io.open(path, "rb") or io.open("data/" .. path, "rb")
  if not f then io.stderr:write("loadBytes: could not read " .. tostring(path) .. "\n") return nil end
  local s = f:read("a") f:close()
  local t = {}
  for i = 1, #s do t[i] = s:byte(i) end
  return t
end
-- saveBytes("file", list): each number becomes one byte
function saveBytes(path, list)
  local f, why = io.open(path, "wb")
  if not f then io.stderr:write("saveBytes: could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n") return false end
  local parts = {}
  for i, b in ipairs(list) do parts[i] = string.char(math.floor(b) % 256) end
  f:write(table.concat(parts)) f:close()
  return true
end
-- float("3.5") -> 3.5, byte(200) -> -56 (Java's signed byte), char(65) -> "A"
function float(v) if type(v) == "boolean" then return v and 1.0 or 0.0 end return (tonumber(v) or 0) + 0.0 end
function byte(v) local b = math.floor(tonumber(v) or 0) % 256 if b > 127 then b = b - 256 end return b end
function char(v) if type(v) == "string" then return v:sub(1, 1) end return utf8.char(math.floor(v)) end

-- createInput("file") / createOutput("file"): a file to read or write bytes
-- with :read / :write / :close (Lua's own file object). Looked for as given,
-- then in data/.
function createInput(path)
  local f = io.open(path, "rb") or io.open("data/" .. path, "rb")
  if not f then io.stderr:write("createInput: could not open " .. tostring(path) .. "\n") end
  return f
end
function createOutput(path)
  local f, why = io.open(path, "wb")
  if not f then io.stderr:write("createOutput: could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n") end
  return f
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
PVector.toString = PVector.__tostring
-- array(): { x, y, z };  get(): a copy, like copy()
function PVector:array() return { self.x, self.y, self.z } end
function PVector:get() return vec(self.x, self.y, self.z) end
function PVector:equals(v) return isvec(v) and self.x == v.x and self.y == v.y and self.z == v.z end
PVector.heading2D = PVector.heading
-- setHeading(a): points the vector at angle a, keeping its length
function PVector:setHeading(a)
  local m = self:mag()
  self.x, self.y = m * math.cos(a), m * math.sin(a)
  return self
end

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

-- ── Movie and Capture (need ffmpeg) ───────────────────────────────────────
-- local m = Movie("clip.mp4")   m:loop()   if m:available() then m:read() end   image(m, 0, 0)
-- m:play() m:pause() m:stop() m:jump(seconds) m:speed(rate) m:time() m:duration()
-- local cam = Capture(640, 480)   cam:start()   if cam:available() then cam:read() end   image(cam, 0, 0)
-- Capture.list() gives the camera names; Capture(640, 480, name) opens one.
do
  local new_movie, new_capture, list, op = __movieNew, __captureNew, __captureList, __video
  __movieNew, __captureNew, __captureList, __video = nil, nil, nil, nil
  local MovieObj, CaptureObj = {}, {}
  MovieObj.__index, CaptureObj.__index = MovieObj, CaptureObj
  for _, name in ipairs({ "play", "loop", "noLoop", "pause", "stop", "jump", "speed", "time", "duration",
                          "frameRate", "isPlaying", "available", "read" }) do
    MovieObj[name] = function(self, x) return op(self.handle, name, x) end
  end
  function MovieObj:volume() end
  for _, name in ipairs({ "start", "stop", "available", "read" }) do
    CaptureObj[name] = function(self, x) return op(self.handle, name, x) end
  end
  MovieObj.__tostring = function(m) return "movie " .. m.width .. "x" .. m.height end
  CaptureObj.__tostring = function(c) return "capture " .. c.width .. "x" .. c.height end
  Movie = setmetatable({}, { __call = function(_, path)
    local h, img, w, ht = new_movie(path)
    return setmetatable({ handle = h, img = img, width = w, height = ht }, MovieObj)
  end })
  Capture = setmetatable({ list = function() return list() end }, { __call = function(_, w, h, name, fps)
    local hd, img = new_capture(w, h, name, fps)
    return setmetatable({ handle = hd, img = img, width = w, height = h }, CaptureObj)
  end })
  -- image(m, ...) and texture(m) take movies and cameras too
  local drawImage, setTexture = image, texture
  function image(img, ...)
    local mt = getmetatable(img)
    if mt == MovieObj or mt == CaptureObj then return drawImage(img.img, ...) end
    return drawImage(img, ...)
  end
  function texture(img)
    local mt = getmetatable(img)
    if mt == MovieObj or mt == CaptureObj then return setTexture(img.img) end
    return setTexture(img)
  end
end

-- shapeMode: the engine handles loaded shapes; shapes made in code ask here
do
  local engineShapeMode, mode = shapeMode, 0
  function shapeMode(m) mode = m engineShapeMode(m) end
  function __shapeModeNow() return mode end
end

-- ── XML ───────────────────────────────────────────────────────────────────
-- local xml = loadXML("data.xml")          -- nil if it can't be read
-- for _, item in ipairs(xml:getChildren("item")) do print(item:getString("name")) end
-- xml:getChild("a/b")  xml:getInt("size")  xml:getContent()  xml:addChild("new")
-- saveXML(xml, "out.xml")   parseXML(text)   xml:format(2)
do
  local parse = __parseXML
  __parseXML = nil
  local XML = {}
  XML.__index = XML
  local function wrap(t)
    local x = setmetatable({ name = t.name, attrs = t.attrs or {}, order = t.order or {}, content = t.content or "", children = {} }, XML)
    for i, c in ipairs(t.children or {}) do x.children[i] = wrap(c) x.children[i].parent = x end
    return x
  end
  function XML:getName() return self.name end
  function XML:setName(n) self.name = n return self end
  function XML:hasChildren() return #self.children > 0 end
  function XML:getChildCount() return #self.children end
  function XML:listChildren() local t = {} for i, c in ipairs(self.children) do t[i] = c.name end return t end
  function XML:getChild(path)
    if type(path) == "number" then return self.children[path + 1] end   -- counts from 0, as in Processing
    local cur = self
    for part in tostring(path):gmatch("[^/]+") do
      local found
      for _, c in ipairs(cur.children) do if c.name == part then found = c break end end
      if not found then return nil end
      cur = found
    end
    return cur
  end
  function XML:getChildren(path)
    if not path or path == "" then local t = {} for i, c in ipairs(self.children) do t[i] = c end return t end
    local parent, last = tostring(path):match("^(.*)/([^/]+)$")
    local p = self
    if parent then p = self:getChild(parent) if not p then return {} end else last = path end
    local t = {}
    for _, c in ipairs(p.children) do if c.name == last then t[#t + 1] = c end end
    return t
  end
  function XML:addChild(child)
    if type(child) == "string" then child = wrap({ name = child }) end
    child.parent = self
    self.children[#self.children + 1] = child
    return child
  end
  function XML:removeChild(child)
    for i, c in ipairs(self.children) do
      if c == child or c.name == child then table.remove(self.children, i) break end
    end
    return self
  end
  function XML:getAttributeCount() return #self.order end
  function XML:listAttributes() local t = {} for i, k in ipairs(self.order) do t[i] = k end return t end
  function XML:hasAttribute(k) return self.attrs[k] ~= nil end
  function XML:getString(k, default) local v = self.attrs[k] if v == nil then return default end return v end
  function XML:getInt(k, default) local v = tonumber(self.attrs[k]) return v and math.floor(v) or (default or 0) end
  function XML:getFloat(k, default) return tonumber(self.attrs[k]) or (default or 0) end
  function XML:setString(k, v)
    if self.attrs[k] == nil then self.order[#self.order + 1] = k end
    self.attrs[k] = tostring(v)
    return self
  end
  XML.setInt, XML.setFloat = XML.setString, XML.setString
  function XML:removeAttribute(k)
    self.attrs[k] = nil
    for i, o in ipairs(self.order) do if o == k then table.remove(self.order, i) break end end
    return self
  end
  function XML:getContent() return self.content end
  function XML:getIntContent() return math.floor(tonumber(self.content) or 0) end
  function XML:getFloatContent() return tonumber(self.content) or 0 end
  function XML:setContent(t) self.content = tostring(t) return self end
  local function esc(v) return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")) end
  local function write(x, out, indent, depth)
    local pad = indent >= 0 and string.rep(" ", indent * depth) or ""
    local nl = indent >= 0 and "\n" or ""
    local parts = { pad, "<", x.name }
    for _, k in ipairs(x.order) do if x.attrs[k] ~= nil then parts[#parts + 1] = " " .. k .. '="' .. esc(x.attrs[k]) .. '"' end end
    if #x.children == 0 and x.content == "" then
      parts[#parts + 1] = "/>" .. nl
      out[#out + 1] = table.concat(parts)
      return
    end
    parts[#parts + 1] = ">"
    if #x.children == 0 then
      parts[#parts + 1] = esc(x.content)
      out[#out + 1] = table.concat(parts)
    else
      out[#out + 1] = table.concat(parts) .. nl
      for _, c in ipairs(x.children) do write(c, out, indent, depth + 1) end
      out[#out + 1] = pad
    end
    out[#out + 1] = "</" .. x.name .. ">" .. nl
  end
  function XML:format(indent)
    local out = {}
    write(self, out, indent or 2, 0)
    return table.concat(out)
  end
  -- Processing's long and double versions are the same numbers in Lua
  function XML:getLong(k, default) local v = tonumber(self.attrs[k]) if v == nil then return default or 0 end v = math.floor(v) return math.tointeger(v) or v end
  XML.getDouble = XML.getFloat
  XML.setLong, XML.setDouble = XML.setString, XML.setString
  function XML:getLongContent(default) local v = tonumber(self.content) if v == nil then return default or 0 end v = math.floor(v) return math.tointeger(v) or v end
  function XML:getDoubleContent(default) return tonumber(self.content) or (default or 0) end
  XML.setIntContent, XML.setFloatContent = XML.setContent, XML.setContent
  XML.setLongContent, XML.setDoubleContent = XML.setContent, XML.setContent
  -- getLocalName(): the name without a "prefix:"
  function XML:getLocalName() return (self.name:match(":([^:]*)$")) or self.name end
  function XML:getParent() return self.parent end
  -- trim(): drops the space around text, here and below
  function XML:trim()
    self.content = self.content:match("^%s*(.-)%s*$")
    for _, c in ipairs(self.children) do c:trim() end
    return self
  end
  function XML:save(path) return saveXML(self, path) end
  function XML:print() print(self:format(2)) end
  XML.toString = function(self) return self:format(-1) end
  XML.__tostring = function(self) return self:format(2) end
  function parseXML(text)
    local t, why = parse(tostring(text))
    if not t then io.stderr:write("parseXML: " .. tostring(why) .. "\n") return nil end
    return wrap(t)
  end
  function loadXML(path)
    local lines = loadStrings(path)
    if not lines then io.stderr:write("loadXML: could not open " .. tostring(path) .. "\n") return nil end
    local t, why = parse(table.concat(lines, "\n"))
    if not t then io.stderr:write("loadXML: " .. tostring(path) .. ": " .. tostring(why) .. "\n") return nil end
    return wrap(t)
  end
  function saveXML(xml, path)
    local f = io.open(path, "w")
    if not f then io.stderr:write("saveXML: could not write " .. tostring(path) .. "\n") return false end
    f:write('<?xml version="1.0" encoding="UTF-8"?>\n', xml:format(2))
    f:close()
    return true
  end
  -- an empty element to build on, like new XML("name")
  XML.new = function(name) return wrap({ name = name }) end
  _G.XML = setmetatable({}, { __index = XML, __call = function(_, name) return wrap({ name = name }) end })
end

-- ── Writers, readers, file dialogs ────────────────────────────────────────
-- local out = createWriter("out.txt")  out:println("hi")  out:flush()  out:close()
-- local r = createReader("in.txt")  local line = r:readLine()   -- nil at the end
-- selectInput("Pick a file", "fileChosen")  calls fileChosen(path), or fileChosen(nil)
do
  local Writer, Reader = {}, {}
  Writer.__index, Reader.__index = Writer, Reader
  local function text(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return table.concat(t, " ") end
  function Writer:print(...) if self.f then self.f:write(text(...)) end end
  function Writer:println(...) if self.f then self.f:write(text(...), "\n") end end
  function Writer:flush() if self.f then self.f:flush() end end
  function Writer:close() if self.f then self.f:close() self.f = nil end end
  function createWriter(path)
    local dir = tostring(path):match("^(.*)/[^/]*$")
    if dir and dir ~= "" then os.execute((package.config:sub(1, 1) == "\\" and 'mkdir "' or 'mkdir -p "') .. dir .. '"') end
    local f, why = io.open(path, "w")
    if not f then io.stderr:write("createWriter: " .. tostring(why) .. "\n") end
    return setmetatable({ f = f }, Writer)
  end
  function Reader:readLine() if self.f then return self.f:read("l") end end
  function Reader:close() if self.f then self.f:close() self.f = nil end end
  function createReader(path)
    local f = io.open(path, "r") or io.open("data/" .. tostring(path), "r")
    if not f then io.stderr:write("createReader: could not open " .. tostring(path) .. "\n") end
    return setmetatable({ f = f }, Reader)
  end
  local dialogs = { selectInput = __selectInput, selectOutput = __selectOutput, selectFolder = __selectFolder }
  __selectInput, __selectOutput, __selectFolder = nil, nil, nil
  for name, ask in pairs(dialogs) do
    _G[name] = function(prompt, callback)
      local path = ask(prompt)
      local f = type(callback) == "function" and callback or _G[callback]
      if type(f) == "function" then f(path) end
      return path
    end
  end
end

-- ── Arrays, as Processing has them (lists counted from 1 here) ────────────
function append(list, v) local t = {} for i, x in ipairs(list) do t[i] = x end t[#t + 1] = v return t end
function shorten(list) local t = {} for i = 1, #list - 1 do t[i] = list[i] end return t end
function expand(list, n) local t = {} for i, x in ipairs(list) do t[i] = x end return t end
function concat(a, b) local t = {} for _, x in ipairs(a) do t[#t + 1] = x end for _, x in ipairs(b) do t[#t + 1] = x end return t end
function subset(list, start, count)
  local t = {}
  local stop = count and (start + count - 1) or #list
  for i = start, math.min(stop, #list) do t[#t + 1] = list[i] end
  return t
end
function splice(list, v, at)
  local t = {}
  for i = 1, at - 1 do t[#t + 1] = list[i] end
  if type(v) == "table" then for _, x in ipairs(v) do t[#t + 1] = x end else t[#t + 1] = v end
  for i = at, #list do t[#t + 1] = list[i] end
  return t
end
function arrayCopy(src, a, b, c, d)
  if b == nil then for i, x in ipairs(src) do a[i] = x end return end   -- arrayCopy(src, dst)
  if c == nil then for i = 1, b do a[i] = src[i] end return end           -- arrayCopy(src, dst, n)
  for i = 0, d - 1 do b[c + i] = src[a + i] end                          -- arrayCopy(src, from, dst, to, n)
end
function reverse(list) local t = {} for i = #list, 1, -1 do t[#t + 1] = list[i] end return t end
function sort(list, n)
  local t = {} for i, x in ipairs(list) do t[i] = x end
  if n and n < #t then
    local head = subset(t, 1, n) table.sort(head)
    for i = 1, n do t[i] = head[i] end
    return t
  end
  table.sort(t)
  return t
end

-- thread("work") runs work() a step at a time between frames: it can call
-- coroutine.yield() to let the sketch draw. Without yields it runs to the end.
do
  local running = {}
  function thread(fn)
    local f = type(fn) == "function" and fn or _G[fn]
    if type(f) ~= "function" then error("thread() expects a function or the name of one", 2) end
    running[#running + 1] = coroutine.create(f)
  end
  function __runThreads()
    for i = #running, 1, -1 do
      local ok, why = coroutine.resume(running[i])
      if not ok then table.remove(running, i) error(why, 0) end
      if coroutine.status(running[i]) == "dead" then table.remove(running, i) end
    end
  end
end
function requestImage(path) return loadImage(path) end

-- ── Shaders ───────────────────────────────────────────────────────────────
-- local s = loadShader("blur.glsl")      -- a GLSL filter shader, as in Processing
-- s:set("radius", 3)  s:set("center", x, y)  filter(s)
-- loadShader("frag.glsl", "vert.glsl") adds a vertex shader for shader().
-- Runs on the CPU with the default renderer, on the GPU with libprocessing.
do
  local load, fromSource, ok, set, run, shapes = __loadShader, __shaderFromSource, __shaderOk, __shaderSet, __filterShader, __shapeShader
  __loadShader, __shaderFromSource, __shaderOk, __shaderSet, __filterShader, __shapeShader = nil, nil, nil, nil, nil, nil
  local Shader = {}
  Shader.__index = Shader
  function Shader:set(name, ...) set(self.handle, name, ...) return self end
  Shader.__tostring = function() return "shader" end
  function loadShader(frag, vert)
    local h = load(frag, vert)
    if not ok(h) then return nil end
    return setmetatable({ handle = h }, Shader)
  end
  -- a shader from text in the sketch
  function createShader(src, vert)
    local h = fromSource(src, vert)
    if not ok(h) then return nil end
    return setmetatable({ handle = h }, Shader)
  end
  -- shader(s): shapes after it are colored by the shader (vertColor is the
  -- fill); resetShader() goes back to plain fills
  function shader(s)
    if getmetatable(s) ~= Shader then error("shader() expects a shader from loadShader()", 2) end
    shapes(s.handle)
  end
  function resetShader() shapes(nil) end
  local plainFilter = filter
  function filter(kind, ...)
    if getmetatable(kind) == Shader then return run(kind.handle) end
    return plainFilter(kind, ...)
  end
end

-- ── loadShape (SVG) ───────────────────────────────────────────────────────
-- local logo = loadShape("logo.svg")     -- nil if it can't be read
-- shape(logo, 10, 10)   shape(logo, 10, 10, 200, 100)   logo.width, logo.height
-- logo:disableStyle() draws it with the sketch's fill and stroke; logo:enableStyle()
-- goes back to the colors in the file.
do
  local load, draw, style = __loadShape, __shape, __shapeStyle
  __loadShape, __shape, __shapeStyle = nil, nil, nil
  local Shape = {}
  Shape.__index = Shape
  function Shape:disableStyle() style(self.id, false) return self end
  function Shape:enableStyle() style(self.id, true) return self end
  Shape.__tostring = function(s) return "shape " .. s.width .. "x" .. s.height end
  function loadShape(path)
    local id, w, h = load(path)
    if id == 0 then return nil end
    return setmetatable({ id = id, width = w, height = h }, Shape)
  end
  -- shapes made in code (createShape, below) register how to draw themselves here
  __shapeKinds = {}
  function shape(s, ...)
    local mt = getmetatable(s)
    if mt == Shape then return draw(s.id, ...) end
    local own = __shapeKinds[mt]
    if own then return own(s, ...) end
    if s == nil then return end         -- a shape that didn't load: draw nothing, as with a missing image
    error("shape() expects a shape from loadShape() or createShape()", 2)
  end
end

-- ── createShape ───────────────────────────────────────────────────────────
-- A shape built once and drawn many times.
--   local star = createShape()
--   star:beginShape()  star:fill(255, 200, 0)  star:vertex(0, -50) ...  star:endShape(CLOSE)
--   local box  = createShape(RECT, 0, 0, 80, 40)
--   local both = createShape(GROUP)  both:addChild(star)  both:addChild(box)
--   shape(star, x, y)
-- Style calls made on the shape (fill, stroke, strokeWeight, noFill, noStroke)
-- belong to it; a shape without any is drawn with the sketch's current style.
-- s:setFill(c) / s:setStroke(c) / s:setStrokeWeight(w) change them later.
-- s:translate / s:rotate / s:scale turn the shape itself, and add up.
POINT, LINE, TRIANGLE, QUAD, RECT, ELLIPSE, ARC, GROUP, SPHERE, BOX = 2, 4, 8, 16, 30, 31, 32, 0, 40, 41
do
  local Made = {}
  Made.__index = Made
  local primitives = { [POINT] = "point", [LINE] = "line", [TRIANGLE] = "triangle", [QUAD] = "quad",
                       [RECT] = "rect", [ELLIPSE] = "ellipse", [ARC] = "arc", [SPHERE] = "sphere", [BOX] = "box" }
  local recorded = { "vertex", "bezierVertex", "quadraticVertex", "curveVertex", "texture", "normal",
                     "beginContour", "endContour" }
  local styles = { "fill", "stroke", "noFill", "noStroke", "strokeWeight", "strokeCap", "strokeJoin" }

  function createShape(kind, ...)
    local s = setmetatable({ steps = {}, style = {}, moves = {}, children = {}, styled = true }, Made)
    if kind == nil then return s end
    if kind == GROUP then s.group = true return s end
    local name = primitives[kind]
    if not name then error("createShape(): unknown kind of shape", 2) end
    s.steps[1] = { name, ... }
    return s
  end

  function Made:beginShape(kind) self.steps = { { "beginShape", kind } } self.open = true return self end
  function Made:endShape(mode) self.steps[#self.steps + 1] = { "endShape", mode } self.open = false return self end
  for _, name in ipairs(recorded) do
    Made[name] = function(self, ...)
      if not self.open then error(name .. "() on a shape needs beginShape() first", 2) end
      self.steps[#self.steps + 1] = { name, ... }
      return self
    end
  end
  for _, name in ipairs(styles) do
    Made[name] = function(self, ...) self.style[#self.style + 1] = { name, ... } return self end
  end
  -- replace every earlier call of one kind
  local function restyle(self, drop, entry)
    local kept = {}
    for _, st in ipairs(self.style) do
      local gone = false
      for _, d in ipairs(drop) do if st[1] == d then gone = true end end
      if not gone then kept[#kept + 1] = st end
    end
    kept[#kept + 1] = entry
    self.style = kept
    return self
  end
  function Made:setFill(...) return restyle(self, { "fill", "noFill" }, { "fill", ... }) end
  function Made:setStroke(...) return restyle(self, { "stroke", "noStroke" }, { "stroke", ... }) end
  function Made:setStrokeWeight(w) return restyle(self, { "strokeWeight" }, { "strokeWeight", w }) end
  function Made:disableStyle() self.styled = false for _, c in ipairs(self.children) do c:disableStyle() end return self end
  function Made:enableStyle() self.styled = true for _, c in ipairs(self.children) do c:enableStyle() end return self end

  function Made:rotate(...) self.moves[#self.moves + 1] = { "rotate", ... } return self end
  function Made:rotateX(a) self.moves[#self.moves + 1] = { "rotateX", a } return self end
  function Made:rotateY(a) self.moves[#self.moves + 1] = { "rotateY", a } return self end
  function Made:rotateZ(a) self.moves[#self.moves + 1] = { "rotate", a } return self end
  function Made:translate(x, y, z) self.moves[#self.moves + 1] = { "translate", x, y, z or 0 } return self end

  function Made:scale(...) self.moves[#self.moves + 1] = { "scale", ... } return self end
  function Made:resetMatrix() self.moves = {} return self end

  -- children can be shapes made here or loaded with loadShape()
  function Made:addChild(child)
    local made = getmetatable(child) == Made
    if not made and not (type(child) == "table" and child.id) then error("addChild() expects a shape", 2) end
    local c = self
    while c do      -- a shape can't end up inside itself
      if c == child then error("addChild(): a shape can't be put inside itself", 2) end
      c = c.parent
    end
    if made then child.parent = self end
    self.children[#self.children + 1] = child
    return self
  end
  function Made:getChild(i) return self.children[i + 1] end        -- counts from 0, as in Processing
  function Made:getChildCount() return #self.children end

  -- vertices, counted from 0
  local function nth_vertex(self, i)
    local n = -1
    for _, st in ipairs(self.steps) do
      if st[1] == "vertex" then
        n = n + 1
        if n == i then return st end
      end
    end
  end
  function Made:getVertexCount()
    local n = 0
    for _, st in ipairs(self.steps) do if st[1] == "vertex" then n = n + 1 end end
    return n
  end
  function Made:getVertex(i)
    local st = nth_vertex(self, i)
    if not st then error("getVertex(" .. tostring(i) .. "): the shape has " .. self:getVertexCount() .. " vertices", 2) end
    return st[2], st[3]
  end
  function Made:setVertex(i, x, y)
    local st = nth_vertex(self, i)
    if not st then error("setVertex(" .. tostring(i) .. "): the shape has " .. self:getVertexCount() .. " vertices", 2) end
    st[2], st[3] = x, y
    return self
  end

  local unpack = table.unpack
  local function paint(self, depth)
    if depth > 64 or self.visible == false then return end
    pushMatrix()
    pushStyle()
    for _, mv in ipairs(self.moves) do _G[mv[1]](unpack(mv, 2)) end
    if self.styled then
      for _, st in ipairs(self.style) do _G[st[1]](unpack(st, 2)) end
    end
    if not self.open then
      for _, st in ipairs(self.steps) do _G[st[1]](unpack(st, 2, 9)) end
    end
    for _, child in ipairs(self.children) do
      if getmetatable(child) == Made then paint(child, depth + 1) else shape(child, 0, 0) end
    end
    popStyle()
    popMatrix()
  end
  -- the box around a shape's own vertices, for shapeMode(CENTER) and sizes
  local function bounds(self)
    local x0, y0, x1, y1
    for _, st in ipairs(self.steps) do
      if st[1] == "vertex" and type(st[2]) == "number" and type(st[3]) == "number" then
        x0 = math.min(x0 or st[2], st[2]) x1 = math.max(x1 or st[2], st[2])
        y0 = math.min(y0 or st[3], st[3]) y1 = math.max(y1 or st[3], st[3])
      end
    end
    if not x0 then return 0, 0, 0, 0 end
    return x0, y0, x1 - x0, y1 - y0
  end
  function Made:getWidth() local _, _, w = bounds(self) return w end
  function Made:getHeight() local _, _, _, h = bounds(self) return h end
  __shapeKinds[Made] = function(self, x, y, w, h)
    x, y = x or 0, y or 0
    local mode = __shapeModeNow and __shapeModeNow() or 0
    pushMatrix()
    if w and h then
      if mode == CORNERS then w, h = w - x, h - y
      elseif mode == CENTER then x, y = x - w / 2, y - h / 2 end
      translate(x, y)
      -- a shape made in code is taken as 100 x 100, as in Processing
      scale(w / 100, h / 100)
    else
      if mode == CENTER then local _, _, bw, bh = bounds(self) x, y = x - bw / 2, y - bh / 2 end
      translate(x, y)
    end
    paint(self, 0)
    popMatrix()
  end
  -- ── More of Processing's PShape ────────────────────────────────────────
  -- Getters that take a vertex index in Processing (getFill(i)...) answer
  -- for the whole shape here: style belongs to the shape, not to vertices.
  function Made:getName() return self.name end
  function Made:setName(n) self.name = n return self end
  -- addName(name, child): findChild(name) finds it
  function Made:addName(n, child) self.names = self.names or {} self.names[n] = child return self end
  function Made:findChild(n)
    if self.names and self.names[n] then return self.names[n] end
    for _, c in ipairs(self.children) do
      if c.name == n then return c end
      if getmetatable(c) == Made then local f = c:findChild(n) if f then return f end end
    end
    return nil
  end
  function Made:getParent() return self.parent end
  function Made:getChildren() local t = {} for i, c in ipairs(self.children) do t[i] = c end return t end
  function Made:getChildIndex(child) for i, c in ipairs(self.children) do if c == child then return i - 1 end end return -1 end
  -- removeChild(i), counting from 0
  function Made:removeChild(i)
    local c = table.remove(self.children, i + 1)
    if c and getmetatable(c) == Made then c.parent = nil end
    return self
  end
  function Made:isVisible() return self.visible ~= false end
  function Made:setVisible(on) self.visible = on and true or false return self end

  -- family: GROUP, PShape.PRIMITIVE for createShape(RECT, ...), PShape.PATH
  -- for one built with beginShape()
  function Made:getFamily()
    if self.family then return self.family end
    if self.group then return GROUP end
    local first = self.steps[1]
    if first and first[1] ~= "beginShape" then return PShape.PRIMITIVE end
    return PShape.PATH
  end
  function Made:setFamily(f) self.family = f return self end
  function Made:getKind()
    local first = self.steps[1]
    if not first then return 0 end
    if first[1] == "beginShape" then return first[2] or POLYGON end
    for kind, name in pairs(primitives) do if name == first[1] then return kind end end
    return 0
  end
  function Made:setKind(kind)
    local first = self.steps[1]
    if first and first[1] == "beginShape" then first[2] = kind end
    return self
  end
  -- createShape(RECT, 0, 0, 80, 40):getParams() -> { 0, 0, 80, 40 }
  function Made:getParams()
    local first, out = self.steps[1], {}
    if first and first[1] ~= "beginShape" then for i = 2, #first do out[i - 1] = first[i] end end
    return out
  end
  function Made:getParam(i) return self:getParams()[i + 1] end
  function Made:isClosed()
    for _, st in ipairs(self.steps) do if st[1] == "endShape" then return st[2] == CLOSE end end
    return false
  end

  -- vertices: x, y, z, u, v from what vertex() was given
  local function parts(st)
    local n = 0
    for i = 2, 6 do if st[i] ~= nil then n = i - 1 end end
    if n == 3 then return st[2], st[3], st[4] end
    if n == 4 then return st[2], st[3], 0, st[4], st[5] end
    if n >= 5 then return st[2], st[3], st[4], st[5], st[6] end
    return st[2], st[3], 0
  end
  local function vertexAt(self, i)
    local st = nth_vertex(self, i)
    if not st then error("vertex " .. tostring(i) .. ": the shape has " .. self:getVertexCount() .. " vertices", 3) end
    return st
  end
  function Made:getVertexX(i) local x = parts(vertexAt(self, i)) return x end
  function Made:getVertexY(i) local _, y = parts(vertexAt(self, i)) return y end
  function Made:getVertexZ(i) local _, _, z = parts(vertexAt(self, i)) return z end
  function Made:getTextureU(i) local _, _, _, u = parts(vertexAt(self, i)) return u or 0 end
  function Made:getTextureV(i) local _, _, _, _, v = parts(vertexAt(self, i)) return v or 0 end
  -- setTextureUV(i, u, v)
  function Made:setTextureUV(i, u, v)
    local st = vertexAt(self, i)
    local x, y, z = parts(st)
    if z ~= 0 then self.steps[self:stepIndex(st)] = { "vertex", x, y, z, u, v }
    else self.steps[self:stepIndex(st)] = { "vertex", x, y, u, v } end
    return self
  end
  function Made:stepIndex(st) for i, s in ipairs(self.steps) do if s == st then return i end end end
  -- normal(x, y, z) given before vertex i, or (0, 0, 1)
  function Made:getNormal(i)
    local n, cur = -1, { 0, 0, 1 }
    for _, st in ipairs(self.steps) do
      if st[1] == "normal" then cur = { st[2] or 0, st[3] or 0, st[4] or 0 }
      elseif st[1] == "vertex" then n = n + 1 if n == i then break end end
    end
    return createVector(cur[1], cur[2], cur[3])
  end
  function Made:getNormalX(i) return self:getNormal(i).x end
  function Made:getNormalY(i) return self:getNormal(i).y end
  function Made:getNormalZ(i) return self:getNormal(i).z end
  function Made:setNormal(i, x, y, z) return self end
  -- vertex codes: VERTEX, BEZIER_VERTEX, QUADRATIC_VERTEX, CURVE_VERTEX, BREAK
  local codes = { vertex = VERTEX, bezierVertex = BEZIER_VERTEX, quadraticVertex = QUADRATIC_VERTEX,
                  curveVertex = CURVE_VERTEX, beginContour = BREAK }
  function Made:getVertexCodes()
    local out = {}
    for _, st in ipairs(self.steps) do local c = codes[st[1]] if c then out[#out + 1] = c end end
    return out
  end
  function Made:getVertexCodeCount() return #self:getVertexCodes() end
  function Made:getVertexCode(i) return self:getVertexCodes()[i + 1] end
  -- setPath({ { x, y }, { x, y, z }, ... }) or setPath(count, list): new vertices
  function Made:setPath(a, b)
    local list = type(a) == "table" and a or b
    local kept, first, last = {}, nil, nil
    for _, st in ipairs(self.steps) do
      if st[1] == "beginShape" then first = st elseif st[1] == "endShape" then last = st end
    end
    kept[1] = first or { "beginShape" }
    local n = type(a) == "number" and a or #list
    for i = 1, n do local v = list[i] kept[#kept + 1] = { "vertex", v[1], v[2], v[3] } end
    kept[#kept + 1] = last or { "endShape" }
    self.steps, self.open = kept, false
    return self
  end
  function Made:is3D()
    if self.force3D ~= nil then return self.force3D end
    for _, st in ipairs(self.steps) do
      if st[1] == "sphere" or st[1] == "box" then return true end
      if st[1] == "vertex" then local _, _, z = parts(st) if z ~= 0 then return true end end
    end
    for _, c in ipairs(self.children) do if getmetatable(c) == Made and c:is3D() then return true end end
    return false
  end
  function Made:is2D() return not self:is3D() end
  function Made:set3D(on) self.force3D = on and true or false return self end
  function Made:getDepth()
    local lo, hi
    for _, st in ipairs(self.steps) do
      if st[1] == "vertex" then local _, _, z = parts(st) lo = math.min(lo or z, z) hi = math.max(hi or z, z) end
    end
    return lo and (hi - lo) or 0
  end
  -- contains(x, y): inside the outline (even-odd rule)
  function Made:contains(x, y)
    local pts = {}
    for _, st in ipairs(self.steps) do if st[1] == "vertex" then pts[#pts + 1] = { st[2], st[3] } end end
    if #pts == 0 and self.steps[1] and self.steps[1][1] == "rect" then
      local p = self.steps[1]
      return x >= p[2] and x <= p[2] + p[4] and y >= p[3] and y <= p[3] + p[5]
    end
    local inside, j = false, #pts
    for i = 1, #pts do
      local a, b = pts[i], pts[j]
      if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then inside = not inside end
      j = i
    end
    return inside
  end

  -- more style the shape keeps: tint, materials, details, colorMode
  for _, name in ipairs({ "tint", "noTint", "ambient", "emissive", "specular", "shininess", "colorMode",
                          "bezierDetail", "curveDetail", "curveTightness", "textureMode" }) do
    Made[name] = function(self, ...) self.style[#self.style + 1] = { name, ... } return self end
  end
  function Made:setTint(...) return restyle(self, { "tint", "noTint" }, { "tint", ... }) end
  function Made:setStrokeCap(c) return restyle(self, { "strokeCap" }, { "strokeCap", c }) end
  function Made:setStrokeJoin(j) return restyle(self, { "strokeJoin" }, { "strokeJoin", j }) end
  function Made:setAmbient(...) return restyle(self, { "ambient" }, { "ambient", ... }) end
  function Made:setEmissive(...) return restyle(self, { "emissive" }, { "emissive", ... }) end
  function Made:setSpecular(...) return restyle(self, { "specular" }, { "specular", ... }) end
  function Made:setShininess(s) return restyle(self, { "shininess" }, { "shininess", s }) end
  function Made:setTextureMode(m) return restyle(self, { "textureMode" }, { "textureMode", m }) end
  -- setTexture(img) / noTexture(): the image on the shape's vertices
  function Made:setTexture(img)
    local kept = {}
    for _, st in ipairs(self.steps) do if st[1] ~= "texture" then kept[#kept + 1] = st end end
    if img ~= nil then table.insert(kept, (kept[1] and kept[1][1] == "beginShape") and 2 or 1, { "texture", img }) end
    self.steps = kept
    return self
  end
  function Made:noTexture() return self:setTexture(nil) end
  -- the last value given, as a color (nil when none was)
  local function lastStyle(self, names)
    for i = #self.style, 1, -1 do
      local st = self.style[i]
      for _, n in ipairs(names) do if st[1] == n then return st end end
    end
  end
  local function styleColor(self, name)
    local st = lastStyle(self, { name, "no" .. name:sub(1, 1):upper() .. name:sub(2) })
    if not st or st[1] ~= name then return nil end
    return color(table.unpack(st, 2))
  end
  function Made:getFill() return styleColor(self, "fill") end
  function Made:getStroke() return styleColor(self, "stroke") end
  function Made:getTint() return styleColor(self, "tint") end
  function Made:getAmbient() return styleColor(self, "ambient") end
  function Made:getEmissive() return styleColor(self, "emissive") end
  function Made:getSpecular() return styleColor(self, "specular") end
  function Made:getStrokeWeight() local st = lastStyle(self, { "strokeWeight" }) return st and st[2] or 1 end
  function Made:getShininess() local st = lastStyle(self, { "shininess" }) return st and st[2] or 0 end
  -- applyMatrix(m) with a matrix from getMatrix(), or 6 / 16 numbers
  function Made:applyMatrix(m, ...)
    if type(m) == "table" then m = { m:array() } else m = { m, ... } end
    self.moves[#self.moves + 1] = { "applyMatrix", table.unpack(m[1] and type(m[1]) == "table" and m[1] or m) }
    return self
  end
  -- attrib values recorded with the vertices
  for _, name in ipairs({ "attrib", "attribPosition", "attribNormal", "attribColor" }) do
    Made[name] = function(self, ...) self.steps[#self.steps + 1] = { name, ... } return self end
  end
  Made.__tostring = function(s) return s.group and ("group of " .. #s.children .. " shapes") or "shape" end
end

-- ── loadTable (CSV / TSV) ─────────────────────────────────────────────────
-- local t = loadTable("scores.csv", "header")     -- nil if it can't be read
-- t:getRowCount()  t:getColumnCount()
-- t:getString(row, "name")  t:getInt(row, 2)  t:getFloat(row, "score")   rows and columns count from 0
-- for row in t:rows() do print(row:getString("name")) end
-- t:addRow()  t:setString(row, col, v)  t:setInt / setFloat   saveTable(t, "out.csv")
-- Without "header" the columns only have numbers. A .tsv file (or the
-- option "tsv") is split on tabs.
do
  local Table, Row = {}, {}
  Table.__index, Row.__index = Table, Row

  -- one record of CSV text starting at pos -> list of fields, position after it
  local function record(text, pos, sep)
    local fields, n = {}, 0
    local len = #text
    while true do
      local c = text:sub(pos, pos)
      local value
      if c == '"' then
        local parts, i = {}, pos + 1
        while true do
          local q = text:find('"', i, true)
          if not q then parts[#parts + 1] = text:sub(i) pos = len + 1 break end
          parts[#parts + 1] = text:sub(i, q - 1)
          if text:sub(q + 1, q + 1) == '"' then parts[#parts + 1] = '"' i = q + 2
          else pos = q + 1 break end
        end
        value = table.concat(parts)
        -- anything between the closing quote and the separator is dropped
        local stop = text:find("[" .. sep .. "\r\n]", pos) or len + 1
        pos = stop
      else
        local stop = text:find("[" .. sep .. "\r\n]", pos) or len + 1
        value = text:sub(pos, stop - 1)
        pos = stop
      end
      n = n + 1
      fields[n] = value
      local d = text:sub(pos, pos)
      if d == sep then pos = pos + 1
      else
        if d == "\r" then pos = pos + 1 if text:sub(pos, pos) == "\n" then pos = pos + 1 end
        elseif d == "\n" then pos = pos + 1 end
        return fields, pos
      end
    end
  end

  local function column(t, col)
    if type(col) == "number" then
      if math.type(col) ~= "integer" then col = math.floor(col) end
      return col
    end
    local i = t.index[col]
    if i == nil then error('this table has no column "' .. tostring(col) .. '"', 3) end
    return i
  end
  local function cell(t, row, col)
    local r = t.data[row]
    if r == nil then error("row " .. tostring(row) .. " is outside the table (it has " .. #t.data + (t.data[0] and 1 or 0) .. " rows)", 3) end
    return r[column(t, col)]
  end

  function Table:getRowCount() return self.count end
  function Table:getColumnCount() return self.columns end
  function Table:getColumnTitles()
    local out = {}
    for i = 0, self.columns - 1 do out[i + 1] = self.titles[i] or "" end
    return out
  end
  function Table:getString(row, col) local v = cell(self, row, col) return v == nil and "" or tostring(v) end
  function Table:getFloat(row, col) return tonumber(cell(self, row, col)) or 0 end
  function Table:getInt(row, col)
    local v = tonumber(cell(self, row, col)) or 0
    return v >= 0 and math.floor(v) or math.ceil(v)
  end
  local function put(t, row, col, v)
    if t.data[row] == nil then error("row " .. tostring(row) .. " is outside the table", 3) end
    local c = column(t, col)
    if c < 0 then error("column " .. c .. " is outside the table", 3) end
    t.data[row][c] = v
    if c >= t.columns then t.columns = c + 1 end
  end
  function Table:setString(row, col, v) put(self, row, col, tostring(v)) end
  function Table:setInt(row, col, v) put(self, row, col, tostring(math.floor(tonumber(v) or 0))) end
  function Table:setFloat(row, col, v) put(self, row, col, tostring(tonumber(v) or 0)) end
  -- addRow() -> the new row
  function Table:addRow()
    self.data[self.count] = {}
    self.count = self.count + 1
    return setmetatable({ table = self, index = self.count - 1 }, Row)
  end
  function Table:addColumn(title)
    if title ~= nil then self.titles[self.columns] = tostring(title) self.index[tostring(title)] = self.columns end
    self.columns = self.columns + 1
  end
  function Table:getRow(i)
    if self.data[i] == nil then error("row " .. tostring(i) .. " is outside the table", 2) end
    return setmetatable({ table = self, index = i }, Row)
  end
  -- for row in t:rows() do ... end
  function Table:rows()
    local i = -1
    return function()
      i = i + 1
      if i < self.count then return setmetatable({ table = self, index = i }, Row) end
    end
  end
  -- removeRow(i): the rows after it move up one
  function Table:removeRow(i)
    if self.data[i] == nil then error("row " .. tostring(i) .. " is outside the table", 2) end
    for r = i, self.count - 2 do self.data[r] = self.data[r + 1] end
    self.data[self.count - 1] = nil
    self.count = self.count - 1
  end
  function Table:clearRows() self.data = {} self.count = 0 end
  -- findRow("Pep", "name") -> the first matching row, or nil
  function Table:findRow(value, col)
    local c = column(self, col)
    value = tostring(value)
    for i = 0, self.count - 1 do
      local v = self.data[i][c]
      if v ~= nil and tostring(v) == value then return setmetatable({ table = self, index = i }, Row) end
    end
    return nil
  end
  -- findRows("red", "color") -> a list of every matching row
  function Table:findRows(value, col)
    local c = column(self, col)
    value = tostring(value)
    local out = {}
    for i = 0, self.count - 1 do
      local v = self.data[i][c]
      if v ~= nil and tostring(v) == value then out[#out + 1] = setmetatable({ table = self, index = i }, Row) end
    end
    return out
  end
  -- every value in one column, as text / whole numbers / numbers
  function Table:getStringColumn(col)
    local c, out = column(self, col), {}
    for i = 0, self.count - 1 do local v = self.data[i][c] out[i + 1] = v == nil and "" or tostring(v) end
    return out
  end
  function Table:getFloatColumn(col)
    local out = self:getStringColumn(col)
    for i, v in ipairs(out) do out[i] = tonumber(v) or 0 end
    return out
  end
  function Table:getIntColumn(col)
    local out = self:getFloatColumn(col)
    for i, v in ipairs(out) do out[i] = v >= 0 and math.floor(v) or math.ceil(v) end
    return out
  end
  -- sort("score"): by number if every cell is one, else as text. sortReverse for high to low.
  local function sortBy(t, col, reverse)
    local c = column(t, col)
    local rows, numeric = {}, true
    for i = 0, t.count - 1 do
      rows[i + 1] = t.data[i]
      if tonumber(t.data[i][c]) == nil then numeric = false end
    end
    local key = numeric and function(r) return tonumber(r[c]) end
                         or function(r) return r[c] == nil and "" or tostring(r[c]) end
    -- stable: equal keys keep their order
    for i, r in ipairs(rows) do r.__order = i end
    table.sort(rows, function(a, b)
      local ka, kb = key(a), key(b)
      if ka == kb then return a.__order < b.__order end
      if reverse then return ka > kb end
      return ka < kb
    end)
    for i, r in ipairs(rows) do r.__order = nil t.data[i - 1] = r end
  end
  function Table:sort(col) sortBy(self, col, false) end
  function Table:sortReverse(col) sortBy(self, col, true) end
  -- trim(): spaces off every cell
  function Table:trim()
    for i = 0, self.count - 1 do
      for c, v in pairs(self.data[i]) do if type(v) == "string" then self.data[i][c] = v:match("^%s*(.-)%s*$") end end
    end
  end
  function Row:getString(col) return self.table:getString(self.index, col) end
  function Row:getInt(col) return self.table:getInt(self.index, col) end
  function Row:getFloat(col) return self.table:getFloat(self.index, col) end
  function Row:setString(col, v) self.table:setString(self.index, col, v) end
  function Row:setInt(col, v) self.table:setInt(self.index, col, v) end
  function Row:setFloat(col, v) self.table:setFloat(self.index, col, v) end

  -- ── More of Processing's Table ─────────────────────────────────────────
  -- Rows and columns count from 0. Lists of values come back as plain Lua
  -- lists (from 1), like getStringColumn().
  local function rowOf(t, i) return setmetatable({ table = t, index = i }, Row) end
  local function asText(v) return v == nil and nil or tostring(v) end

  -- setMissingInt(n) and friends: what a getter returns for an empty cell
  function Table:setMissingString(v) self.missingString = v end
  function Table:setMissingInt(v) self.missingInt = v end
  function Table:setMissingLong(v) self.missingInt = v end
  function Table:setMissingFloat(v) self.missingFloat = v end
  function Table:setMissingDouble(v) self.missingFloat = v end
  function Table:getString(row, col)
    local v = cell(self, row, col)
    if v == nil then return self.missingString or "" end
    return tostring(v)
  end
  function Table:getFloat(row, col)
    local v = tonumber(cell(self, row, col))
    if v == nil then return self.missingFloat or 0 end
    return v
  end
  function Table:getInt(row, col)
    local v = tonumber(cell(self, row, col))
    if v == nil then return self.missingInt or 0 end
    v = v >= 0 and math.floor(v) or math.ceil(v)
    return math.tointeger(v) or v
  end
  Table.getDouble, Table.getLong = Table.getFloat, Table.getInt
  Table.setDouble, Table.setLong = Table.setFloat, Table.setInt
  Table.getDoubleColumn, Table.getLongColumn = Table.getFloatColumn, Table.getIntColumn

  function Table:lastRowIndex() return self.count - 1 end
  function Table:hasColumnTitles() return next(self.titles) ~= nil end
  function Table:getColumnTitle(i) return self.titles[i] end
  -- getColumnIndex("name"): an error when there is no such column, as in Processing
  function Table:getColumnIndex(name)
    if type(name) == "number" then return name end
    local i = self.index[tostring(name)]
    if i == nil then error('this table has no column "' .. tostring(name) .. '"', 2) end
    return i
  end
  -- checkColumnIndex("name"): the column's index, adding it when missing
  function Table:checkColumnIndex(name)
    local i = self.index[tostring(name)]
    if i ~= nil then return i end
    self:addColumn(name)
    return self.columns - 1
  end
  local function reindex(t)
    t.index = {}
    for c = t.columns - 1, 0, -1 do local title = t.titles[c] if title ~= nil then t.index[title] = c end end
  end
  function Table:setColumnTitle(i, title)
    if title == nil then self.titles[i] = nil else self.titles[i] = tostring(title) end
    if i >= self.columns then self.columns = i + 1 end
    reindex(self)
    self.header = next(self.titles) ~= nil
  end
  -- setColumnTitles({ "a", "b" }), or nil to drop them
  function Table:setColumnTitles(list)
    self.titles = {}
    if list then for i, title in ipairs(list) do self.titles[i - 1] = tostring(title) end
      if #list > self.columns then self.columns = #list end
    end
    reindex(self)
    self.header = next(self.titles) ~= nil
  end
  function Table:removeTitleRow()
    local titles = self:getStringRow(0)
    self:removeRow(0)
    self:setColumnTitles(titles)
  end

  -- column types: STRING 0, INT 1, LONG 2, FLOAT 3, DOUBLE 4, CATEGORY 5 (or
  -- their names as text). The getters convert either way; the type is kept
  -- for getColumnType().
  local typeNames = { string = 0, int = 1, long = 2, float = 3, double = 4, category = 5 }
  Table.STRING, Table.INT, Table.LONG, Table.FLOAT, Table.DOUBLE, Table.CATEGORY = 0, 1, 2, 3, 4, 5
  local function typeOf(v)
    if type(v) == "string" then return typeNames[v:lower()] or 0 end
    return math.tointeger(v) or 0
  end
  function Table:setColumnType(col, kind)
    self.types = self.types or {}
    self.types[column(self, col)] = typeOf(kind)
  end
  function Table:getColumnType(col) return (self.types or {})[column(self, col)] or 0 end
  function Table:setColumnTypes(list)
    if getmetatable(list) == Table then
      -- another table with "title" and "type" columns
      for r = 0, list.count - 1 do self:setColumnType(list:getString(r, "title"), list:getString(r, "type")) end
      return
    end
    for i, kind in ipairs(list) do self:setColumnType(i - 1, kind) end
  end
  function Table:getColumnTypes()
    local out = {}
    for c = 0, self.columns - 1 do out[c + 1] = self:getColumnType(c) end
    return out
  end

  -- one row as a list of strings / whole numbers / numbers
  function Table:getStringRow(row)
    local out = {}
    for c = 0, self.columns - 1 do out[c + 1] = self:getString(row, c) end
    return out
  end
  function Table:getIntRow(row)
    local out = {}
    for c = 0, self.columns - 1 do out[c + 1] = self:getInt(row, c) end
    return out
  end
  function Table:getFloatRow(row)
    local out = {}
    for c = 0, self.columns - 1 do out[c + 1] = self:getFloat(row, c) end
    return out
  end
  Table.getLongRow, Table.getDoubleRow = Table.getIntRow, Table.getFloatRow

  function Table:getStringList(col) return StringList(self:getStringColumn(col)) end
  function Table:getIntList(col) return IntList(self:getIntColumn(col)) end
  function Table:getFloatList(col) return FloatList(self:getFloatColumn(col)) end
  -- getIntDict(keyColumn, valueColumn) and friends
  local function dict(t, make, getter, kc, vc)
    local d = make()
    for r = 0, t.count - 1 do d:set(t:getString(r, kc), getter(t, r, vc)) end
    return d
  end
  function Table:getStringDict(kc, vc) return dict(self, StringDict, Table.getString, kc, vc) end
  function Table:getIntDict(kc, vc) return dict(self, IntDict, Table.getInt, kc, vc) end
  function Table:getFloatDict(kc, vc) return dict(self, FloatDict, Table.getFloat, kc, vc) end
  function Table:getUnique(col) return StringList(self:getStringColumn(col)):getUnique() end
  function Table:getTally(col) return StringList(self:getStringColumn(col)):getTally() end
  function Table:getOrder(col) return StringList(self:getStringColumn(col)):getOrder() end
  -- getRowMap(col): value -> row
  function Table:getRowMap(col)
    local c, out = column(self, col), {}
    for r = 0, self.count - 1 do local v = self.data[r][c] if v ~= nil then out[tostring(v)] = rowOf(self, r) end end
    return out
  end

  function Table:findRowIndex(value, col)
    local c = column(self, col)
    value = tostring(value)
    for r = 0, self.count - 1 do if asText(self.data[r][c]) == value then return r end end
    return -1
  end
  function Table:findRowIndices(value, col)
    local c, out = column(self, col), {}
    value = tostring(value)
    for r = 0, self.count - 1 do if asText(self.data[r][c]) == value then out[#out + 1] = r end end
    return out
  end
  -- matchRow(regex, col): rows where the regular expression is found in the cell
  local function matches(t, re, col)
    local c, out = column(t, col), {}
    for r = 0, t.count - 1 do
      local v = t.data[r][c]
      if v ~= nil and __regexFind(tostring(v), re) then out[#out + 1] = r end
    end
    return out
  end
  function Table:matchRowIndices(re, col) return matches(self, re, col) end
  function Table:matchRowIndex(re, col) local m = matches(self, re, col) return m[1] or -1 end
  function Table:matchRow(re, col) local m = matches(self, re, col) return m[1] and rowOf(self, m[1]) or nil end
  function Table:matchRows(re, col)
    local out = {}
    for i, r in ipairs(matches(self, re, col)) do out[i] = rowOf(self, r) end
    return out
  end

  -- each cell (in one column, or all) put through f; nil keeps it
  local function eachCell(t, col, f)
    local cols = {}
    if col == nil then for c = 0, t.columns - 1 do cols[#cols + 1] = c end else cols[1] = column(t, col) end
    for r = 0, t.count - 1 do
      for _, c in ipairs(cols) do
        local v = t.data[r][c]
        if v ~= nil then local n = f(tostring(v)) if n ~= nil then t.data[r][c] = n end end
      end
    end
  end
  -- replace(orig, new[, col]): cells that are exactly orig
  function Table:replace(orig, new, col)
    orig = tostring(orig)
    eachCell(self, col, function(v) if v == orig then return tostring(new) end end)
  end
  -- replaceAll(regex, new[, col]): inside every cell; $1 is a group
  function Table:replaceAll(re, new, col)
    eachCell(self, col, function(v) return __regexReplace(v, re, tostring(new)) end)
  end
  -- removeTokens(chars[, col]): those characters out of every cell
  function Table:removeTokens(chars, col)
    local class = "[" .. tostring(chars):gsub("[%]%^%-%%]", "%%%0") .. "]"
    eachCell(self, col, function(v) return (v:gsub(class, "")) end)
  end

  function Table:insertColumn(i, title, kind)
    for r = 0, self.count - 1 do
      local row = self.data[r]
      for c = self.columns - 1, i, -1 do row[c + 1] = row[c] end
      row[i] = nil
    end
    for c = self.columns - 1, i, -1 do self.titles[c + 1] = self.titles[c] end
    self.titles[i] = title ~= nil and tostring(title) or nil
    if self.types then for c = self.columns - 1, i, -1 do self.types[c + 1] = self.types[c] end self.types[i] = nil end
    self.columns = self.columns + 1
    reindex(self)
    if kind ~= nil then self:setColumnType(i, kind) end
  end
  function Table:removeColumn(col)
    local i = column(self, col)
    for r = 0, self.count - 1 do
      local row = self.data[r]
      for c = i, self.columns - 1 do row[c] = row[c + 1] end
    end
    for c = i, self.columns - 1 do self.titles[c] = self.titles[c + 1] end
    if self.types then for c = i, self.columns - 1 do self.types[c] = self.types[c + 1] end end
    self.columns = self.columns - 1
    reindex(self)
  end
  function Table:setColumnCount(n)
    for r = 0, self.count - 1 do for c = n, self.columns - 1 do self.data[r][c] = nil end end
    for c = n, self.columns - 1 do self.titles[c] = nil end
    self.columns = n
    reindex(self)
  end
  function Table:setRowCount(n)
    for r = self.count, n - 1 do self.data[r] = {} end
    for r = n, self.count - 1 do self.data[r] = nil end
    self.count = n
  end
  -- insertRow(i, { values... })
  function Table:insertRow(i, values)
    for r = self.count - 1, i, -1 do self.data[r + 1] = self.data[r] end
    local row = {}
    for c, v in ipairs(values or {}) do row[c - 1] = tostring(v) end
    self.data[i] = row
    self.count = self.count + 1
    if values and #values > self.columns then self.columns = #values end
  end
  -- setRow(i, row): copies the cells of a row (from any table)
  function Table:setRow(i, src)
    if self.data[i] == nil then error("row " .. tostring(i) .. " is outside the table", 2) end
    local row = {}
    if getmetatable(src) == Row then
      for c = 0, src.table.columns - 1 do row[c] = src.table.data[src.index][c] end
    else
      for c, v in ipairs(src) do row[c - 1] = tostring(v) end
    end
    self.data[i] = row
    return rowOf(self, i)
  end
  -- addRows(other): every row of another table, added at the end
  function Table:addRows(src)
    for r = 0, src.count - 1 do
      local row = {}
      for c, v in pairs(src.data[r]) do row[c] = v end
      self.data[self.count] = row
      self.count = self.count + 1
    end
    if src.columns > self.columns then self.columns = src.columns end
  end
  function Table:copy()
    local t = createTable()
    t.header, t.columns, t.count = self.header, self.columns, self.count
    for c, title in pairs(self.titles) do t.titles[c] = title end
    reindex(t)
    if self.types then t.types = {} for c, k in pairs(self.types) do t.types[c] = k end end
    t.missingString, t.missingInt, t.missingFloat = self.missingString, self.missingInt, self.missingFloat
    for r = 0, self.count - 1 do local row = {} for c, v in pairs(self.data[r]) do row[c] = v end t.data[r] = row end
    return t
  end
  -- print(): tab-separated, titles first
  function Table:print()
    if self:hasColumnTitles() then
      local line = {}
      for c = 0, self.columns - 1 do line[c + 1] = self.titles[c] or "" end
      print(table.concat(line, "\t"))
    end
    for r = 0, self.count - 1 do print(table.concat(self:getStringRow(r), "\t")) end
  end
  function Table:save(path, opts) return saveTable(self, path, opts) end

  function Row:getColumnCount() return self.table.columns end
  function Row:getColumnTitle(i) return self.table.titles[i] end
  function Row:getColumnTitles() return self.table:getColumnTitles() end
  function Row:getColumnType(col) return self.table:getColumnType(col) end
  function Row:getColumnTypes() return self.table:getColumnTypes() end
  function Row:getDouble(col) return self.table:getFloat(self.index, col) end
  function Row:getLong(col) return self.table:getInt(self.index, col) end
  function Row:setDouble(col, v) self.table:setFloat(self.index, col, v) end
  function Row:setLong(col, v) self.table:setInt(self.index, col, v) end
  function Row:print() print(table.concat(self.table:getStringRow(self.index), "\t")) end

  local function options(opts, path)
    opts = tostring(opts or "")
    local tsv = opts:find("tsv", 1, true) ~= nil or (opts:find("csv", 1, true) == nil and tostring(path):lower():match("%.tsv$") ~= nil)
    return opts:find("header", 1, true) ~= nil, tsv and "\t" or ","
  end

  -- an empty table to fill in: createTable("name", "score")
  function createTable(...)
    local t = setmetatable({ data = {}, count = 0, columns = 0, titles = {}, index = {}, header = false }, Table)
    for _, title in ipairs { ... } do t:addColumn(title) t.header = true end
    return t
  end

  function loadTable(path, opts)
    local f = io.open(path, "rb")
    if not f then
      f = io.open("data/" .. tostring(path), "rb")
      if not f then
        io.stderr:write("loadTable: could not open " .. tostring(path) .. "\n")
        return nil
      end
    end
    local text = f:read("a"):gsub("^\xEF\xBB\xBF", "")
    f:close()
    local header, sep = options(opts, path)
    local t = createTable()
    t.header = header
    local pos, len = 1, #text
    local first = true
    while pos <= len do
      local fields
      fields, pos = record(text, pos, sep)
      if first and header then
        for i, title in ipairs(fields) do t.titles[i - 1] = title if t.index[title] == nil then t.index[title] = i - 1 end end
        if #fields > t.columns then t.columns = #fields end
      elseif not (#fields == 1 and fields[1] == "") then      -- skip blank lines
        local row = {}
        for i, v in ipairs(fields) do row[i - 1] = v end
        t.data[t.count] = row
        t.count = t.count + 1
        if #fields > t.columns then t.columns = #fields end
      end
      first = false
    end
    return t
  end

  function saveTable(t, path, opts)
    if getmetatable(t) ~= Table then error("saveTable() expects a table from loadTable() or createTable()", 2) end
    local _, sep = options(opts, path)
    local function field(v)
      v = v == nil and "" or tostring(v)
      if v:find('[",\t\r\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
      return v
    end
    local f, why = io.open(path, "w")
    if not f then
      io.stderr:write("saveTable: could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n")
      return false
    end
    local line = {}
    if t.header then
      for c = 0, t.columns - 1 do line[c + 1] = field(t.titles[c]) end
      f:write(table.concat(line, sep), "\n")
    end
    for r = 0, t.count - 1 do
      for c = 0, t.columns - 1 do line[c + 1] = field(t.data[r][c]) end
      f:write(table.concat(line, sep), "\n")
    end
    f:close()
    return true
  end
end

-- ── IntList / FloatList / StringList, IntDict / FloatDict / StringDict ─────
-- Processing's list and dictionary helpers. Indexes count from 0, like
-- Processing: list:get(0) is the first value.
--   local l = IntList(3, 1, 2)   l:append(5)   l:sort()   print(l:get(0), l:size())
--   local d = IntDict()          d:increment("apples")    d:sortValuesReverse()
do
  local function makeList(kind, convert)
    local L = {}
    L.__index = L
    L.__name = kind
    L.__len = function(self) return #self.v end
    L.__tostring = function(self)
      local parts = {}
      for i, x in ipairs(self.v) do parts[i] = tostring(x) end
      return kind .. " size=" .. #self.v .. " [ " .. table.concat(parts, ", ") .. " ]"
    end
    local function idx(self, i, level)
      if type(i) ~= "number" or i < 0 or i >= #self.v or i ~= math.floor(i) then
        error(kind .. ": index " .. tostring(i) .. " is outside the list (size " .. #self.v .. ")", level or 3)
      end
      return i + 1
    end
    local function new(...)
      local self = setmetatable({ v = {} }, L)
      local args = { ... }
      if #args == 1 and type(args[1]) == "table" and getmetatable(args[1]) == nil then args = args[1] end
      if #args == 1 and getmetatable(args[1]) == L then args = args[1].v end
      for i, x in ipairs(args) do self.v[i] = convert(x) end
      return self
    end
    function L:size() return #self.v end
    function L:get(i) return self.v[idx(self, i)] end
    function L:set(i, x)
      if i == #self.v then self.v[i + 1] = convert(x) return end -- set at the end appends
      self.v[idx(self, i)] = convert(x)
    end
    function L:append(x)
      if type(x) == "table" then
        local src = getmetatable(x) and x.v or x
        for _, y in ipairs(src) do self.v[#self.v + 1] = convert(y) end
      else self.v[#self.v + 1] = convert(x) end
    end
    function L:push(x) self:append(x) end
    function L:insert(i, x)
      if i ~= #self.v then idx(self, i) end
      table.insert(self.v, i + 1, convert(x))
    end
    function L:remove(i) return table.remove(self.v, idx(self, i)) end
    function L:removeValue(x)
      x = convert(x)
      for i, y in ipairs(self.v) do if y == x then table.remove(self.v, i) return i - 1 end end
      return -1
    end
    function L:clear() self.v = {} end
    function L:hasValue(x) x = convert(x) for _, y in ipairs(self.v) do if y == x then return true end end return false end
    function L:index(x) x = convert(x) for i, y in ipairs(self.v) do if y == x then return i - 1 end end return -1 end
    function L:sort() table.sort(self.v) end
    function L:sortReverse() table.sort(self.v, function(a, b) return a > b end) end
    function L:reverse()
      local v, n = self.v, #self.v
      for i = 1, n // 2 do v[i], v[n - i + 1] = v[n - i + 1], v[i] end
    end
    function L:shuffle()
      for i = #self.v, 2, -1 do local j = math.floor(random(i)) + 1 if j > i then j = i end self.v[i], self.v[j] = self.v[j], self.v[i] end
    end
    function L:copy() return new(self.v) end
    -- toArray(): a plain Lua list (from 1) of the values
    function L:toArray() local out = {} for i, x in ipairs(self.v) do out[i] = x end return out end
    -- for i, x in l:values() do ... end   (i from 0)
    function L:values()
      local i = 0
      return function() i = i + 1 if self.v[i] ~= nil then return i - 1, self.v[i] end end
    end
    if kind ~= "StringList" then
      function L:sum() local t = 0 for _, x in ipairs(self.v) do t = t + x end return t end
      function L:min()
        if #self.v == 0 then error(kind .. ":min() on an empty list", 2) end
        local m = self.v[1] for _, x in ipairs(self.v) do if x < m then m = x end end return m
      end
      function L:max()
        if #self.v == 0 then error(kind .. ":max() on an empty list", 2) end
        local m = self.v[1] for _, x in ipairs(self.v) do if x > m then m = x end end return m
      end
      function L:add(i, n) self.v[idx(self, i)] = convert(self.v[i + 1] + n) end
      function L:sub(i, n) self.v[idx(self, i)] = convert(self.v[i + 1] - n) end
      function L:mult(i, n) self.v[idx(self, i)] = convert(self.v[i + 1] * n) end
      function L:div(i, n) self.v[idx(self, i)] = convert(self.v[i + 1] / n) end
      function L:increment(i) self:add(i, 1) end
    else
      function L:lower() for i, x in ipairs(self.v) do self.v[i] = x:lower() end end
      function L:upper() for i, x in ipairs(self.v) do self.v[i] = x:upper() end end
      function L:join(sep) return table.concat(self.v, sep or "") end
    end
    -- more of Processing's list methods
    function L:pop()
      if #self.v == 0 then error(kind .. ":pop() on an empty list", 2) end
      return table.remove(self.v)
    end
    function L:appendUnique(x) x = convert(x) if not self:hasValue(x) then self.v[#self.v + 1] = x end end
    L.array = L.toArray
    function L:swap(a, b) local i, j = idx(self, a), idx(self, b) self.v[i], self.v[j] = self.v[j], self.v[i] end
    -- resize(n): cut off the end, or pad with 0 ("" in a StringList)
    function L:resize(n)
      n = math.max(0, math.floor(n))
      local pad = kind == "StringList" and "" or convert(0)
      for i = #self.v + 1, n do self.v[i] = pad end
      for i = #self.v, n + 1, -1 do self.v[i] = nil end
    end
    -- getSubset(start) / getSubset(start, count): a new list
    function L:getSubset(start, count)
      local out = new()
      local stop = count and math.min(start + count, #self.v) or #self.v
      for i = start + 1, stop do out.v[#out.v + 1] = self.v[i] end
      return out
    end
    -- removeValues(x): every x goes, returns how many
    function L:removeValues(x)
      x = convert(x)
      local kept, n = {}, 0
      for _, y in ipairs(self.v) do if y == x then n = n + 1 else kept[#kept + 1] = y end end
      self.v = kept
      return n
    end
    function L:replaceValue(old, value)
      old = convert(old)
      for i, y in ipairs(self.v) do if y == old then self.v[i] = convert(value) return true end end
      return false
    end
    function L:replaceValues(old, value)
      old = convert(old)
      local n = 0
      for i, y in ipairs(self.v) do if y == old then self.v[i] = convert(value) n = n + 1 end end
      return n
    end
    local function pick(self)
      if #self.v == 0 then error(kind .. ": no entries in this list", 3) end
      return math.min(#self.v, math.floor(random(#self.v)) + 1)
    end
    function L:choice() return self.v[pick(self)] end
    function L:removeChoice() return table.remove(self.v, pick(self)) end
    L.random = L.choice
    function L:join(sep) local p = {} for i, x in ipairs(self.v) do p[i] = tostring(x) end return table.concat(p, sep or "") end
    L.toString = L.__tostring
    -- toJSON(): a plain Lua list; the global toJSON() turns it into text
    L.toJSON = L.toArray
    local line = kind == "IntList" and "[%d] %d" or kind == "FloatList" and "[%d] %f" or "[%d] %s"
    function L:print() for i, x in ipairs(self.v) do print(string.format(line, i - 1, x)) end end
    -- save("file.txt"): one value per line
    function L:save(path)
      local f, why = io.open(path, "w")
      if not f then io.stderr:write(kind .. ":save(): could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n") return false end
      for _, x in ipairs(self.v) do f:write(tostring(x), "\n") end
      f:close()
      return true
    end
    if kind ~= "StringList" then
      local function best(self, better)
        if #self.v == 0 then return -1 end
        local b = 1
        for i, x in ipairs(self.v) do if better(x, self.v[b]) then b = i end end
        return b - 1
      end
      function L:minIndex() return best(self, function(a, b) return a < b end) end
      function L:maxIndex() return best(self, function(a, b) return a > b end) end
      L.sumLong, L.sumDouble = L.sum, L.sum
      -- getPercent(): a FloatList of each value divided by the sum
      function L:getPercent()
        local s, out = self:sum(), FloatList()
        for i, x in ipairs(self.v) do out.v[i] = x / s end
        return out
      end
    else
      -- getUnique(): each value once, in order; getTally(): how often each
      -- appears; getOrder(): the index of each (the last one, as in Processing)
      function L:getUnique()
        local seen, out = {}, {}
        for _, x in ipairs(self.v) do if not seen[x] then seen[x] = true out[#out + 1] = x end end
        return out
      end
      function L:getTally() local d = IntDict() for _, x in ipairs(self.v) do d:increment(x) end return d end
      function L:getOrder() local d = IntDict() for i, x in ipairs(self.v) do d:set(x, i - 1) end return d end
    end
    return new, L
  end

  local function toInt(x)
    local n = tonumber(x)
    if n == nil then error("IntList: " .. tostring(x) .. " is not a number", 4) end
    n = n >= 0 and math.floor(n) or math.ceil(n)
    return math.tointeger(n) or n
  end
  local function toFloat(x)
    local n = tonumber(x)
    if n == nil then error("FloatList: " .. tostring(x) .. " is not a number", 4) end
    return n + 0.0
  end
  IntList = makeList("IntList", toInt)
  FloatList = makeList("FloatList", toFloat)
  StringList = makeList("StringList", tostring)

  local function makeDict(kind, convert, numeric)
    local D = {}
    D.__index = D
    D.__name = kind
    D.__tostring = function(self)
      local parts = {}
      for i, k in ipairs(self.k) do parts[i] = string.format("%q: %s", k, tostring(self.v[k])) end
      return kind .. " size=" .. #self.k .. " { " .. table.concat(parts, ", ") .. " }"
    end
    local function new(init)
      local self = setmetatable({ k = {}, v = {} }, D)
      if type(init) == "table" then
        local keys = {}
        for key in pairs(init) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        for _, key in ipairs(keys) do self:set(key, init[key] == nil and init[tonumber(key)] or init[key]) end
      end
      return self
    end
    function D:size() return #self.k end
    function D:hasKey(key) return self.v[tostring(key)] ~= nil end
    -- get(key) -> the value; get(key, default) when it may be missing
    function D:get(key, default)
      local v = self.v[tostring(key)]
      if v == nil then
        if default ~= nil then return default end
        error(kind .. ': no key "' .. tostring(key) .. '"', 2)
      end
      return v
    end
    function D:set(key, value)
      key = tostring(key)
      if self.v[key] == nil then self.k[#self.k + 1] = key end
      self.v[key] = convert(value)
    end
    function D:remove(key)
      key = tostring(key)
      local v = self.v[key]
      if v == nil then return nil end
      self.v[key] = nil
      for i, k in ipairs(self.k) do if k == key then table.remove(self.k, i) break end end
      return v
    end
    function D:clear() self.k = {} self.v = {} end
    function D:keys() local out = {} for i, k in ipairs(self.k) do out[i] = k end return out end
    function D:valueArray() local out = {} for i, k in ipairs(self.k) do out[i] = self.v[k] end return out end
    function D:keyArray() return self:keys() end
    -- for key, value in d:pairs() do ... end, in the dictionary's order
    function D:pairs()
      local i = 0
      return function() i = i + 1 local k = self.k[i] if k ~= nil then return k, self.v[k] end end
    end
    function D:key(i) return self.k[i + 1] end
    function D:value(i) return self.v[self.k[i + 1]] end
    function D:sortKeys() table.sort(self.k) end
    function D:sortKeysReverse() table.sort(self.k, function(a, b) return a > b end) end
    function D:sortValues()
      local v = self.v
      table.sort(self.k, function(a, b) if v[a] == v[b] then return a < b end return v[a] < v[b] end)
    end
    function D:sortValuesReverse()
      local v = self.v
      table.sort(self.k, function(a, b) if v[a] == v[b] then return a < b end return v[a] > v[b] end)
    end
    function D:copy() local c = new() for _, k in ipairs(self.k) do c:set(k, self.v[k]) end return c end
    if numeric then
      function D:add(key, n) key = tostring(key) self:set(key, (self.v[key] or 0) + n) end
      function D:sub(key, n) self:add(key, -n) end
      function D:mult(key, n) key = tostring(key) self:set(key, (self.v[key] or 0) * n) end
      function D:div(key, n) key = tostring(key) self:set(key, (self.v[key] or 0) / n) end
      function D:increment(key) self:add(key, 1) end
      function D:sum() local t = 0 for _, k in ipairs(self.k) do t = t + self.v[k] end return t end
      local function pick(self, better)
        local best
        for _, k in ipairs(self.k) do if best == nil or better(self.v[k], self.v[best]) then best = k end end
        return best
      end
      function D:maxKey() return pick(self, function(a, b) return a > b end) end
      function D:minKey() return pick(self, function(a, b) return a < b end) end
      function D:maxValue() local k = self:maxKey() return k and self.v[k] end
      function D:minValue() local k = self:minKey() return k and self.v[k] end
    end
    -- more of Processing's dictionary methods; indexes count from 0
    local function at(self, i)
      if type(i) ~= "number" or i < 0 or i >= #self.k or i ~= math.floor(i) then
        error(kind .. ": index " .. tostring(i) .. " is outside the dictionary (size " .. #self.k .. ")", 3)
      end
      return i + 1
    end
    function D:index(key) key = tostring(key) for i, k in ipairs(self.k) do if k == key then return i - 1 end end return -1 end
    function D:removeIndex(i)
      local j = at(self, i)
      local key = self.k[j]
      local v = self.v[key]
      table.remove(self.k, j)
      self.v[key] = nil
      return v
    end
    function D:setIndex(i, key, value)
      local j = at(self, i)
      key = tostring(key)
      if self.k[j] ~= key then self.v[self.k[j]] = nil end
      self.k[j] = key
      self.v[key] = convert(value)
    end
    function D:swap(a, b) local i, j = at(self, a), at(self, b) self.k[i], self.k[j] = self.k[j], self.k[i] end
    -- resize(n) only shrinks, as in Processing
    function D:resize(n)
      if n > #self.k then error("resize() can only be used to shrink the dictionary", 2) end
      if n < 1 then error("resize(" .. tostring(n) .. ") is too small, use 1 or higher", 2) end
      for i = #self.k, n + 1, -1 do self.v[self.k[i]] = nil self.k[i] = nil end
    end
    -- for key, value in d:entries() do ... end
    D.entries = D.pairs
    -- for value in d:values() do ... end
    function D:values()
      local i = 0
      return function() i = i + 1 local k = self.k[i] if k ~= nil then return self.v[k] end end
    end
    D.toString = D.__tostring
    -- toJSON(): a plain Lua table of key = value
    function D:toJSON() local t = {} for _, k in ipairs(self.k) do t[k] = self.v[k] end return t end
    function D:print() for _, k in ipairs(self.k) do print(k .. " = " .. tostring(self.v[k])) end end
    -- save("file.tsv"): key, a tab, the value, one entry per line
    function D:save(path)
      local f, why = io.open(path, "w")
      if not f then io.stderr:write(kind .. ":save(): could not write " .. tostring(path) .. " (" .. tostring(why) .. ")\n") return false end
      for _, k in ipairs(self.k) do f:write(k, "\t", tostring(self.v[k]), "\n") end
      f:close()
      return true
    end
    if numeric then
      D.sumLong, D.sumDouble = D.sum, D.sum
      function D:getPercent(key) return self:get(key) / self:sum() end
      function D:maxIndex() local k = self:maxKey() return k and self:index(k) or -1 end
      function D:minIndex() local k = self:minKey() return k and self:index(k) or -1 end
    end
    return new, D
  end
  IntDict = makeDict("IntDict", toInt, true)
  FloatDict = makeDict("FloatDict", toFloat, true)
  StringDict = makeDict("StringDict", tostring, false)
end

-- ── Images and fonts as objects ───────────────────────────────────────────
-- Images and fonts stay plain numbers (handles), so everything that took
-- them still does. Numbers get an __index that answers only for Processing's
-- PImage and PFont names:
--   img.width  img:get(x, y)  img:set(x, y, c)  img:resize(w, h)  img:filter(GRAY)
--   img:loadPixels()  img.pixels[y * img.width + x] = c  img:updatePixels()
--   font:getSize()  font:getName()  font:ascent()  font:width("m")
-- Fonts are numbered from __FONT_BASE up, so a font and an image never share
-- a number. Indexing any other number is still an error.
do
  local FONT_BASE = __FONT_BASE
  local size, loadPx, updatePx, filterImg, blendImg, saveImg, getPx =
    __imgSize, __imgLoadPixels, __imgUpdatePixels, __imgFilter, __imgBlend, __imgSave, __imgGet
  local fontInfo, charWidth = __fontInfo, __fontCharWidth
  __FONT_BASE, __imgSize, __imgLoadPixels, __imgUpdatePixels, __imgFilter, __imgBlend, __imgSave, __imgGet =
    nil, nil, nil, nil, nil, nil, nil, nil
  __fontInfo, __fontCharWidth = nil, nil

  -- fonts: the engine's id plus FONT_BASE (0 still means "didn't load")
  local rawCreate, rawLoad, rawTextFont = createFont, loadFont, textFont
  local function wrapFont(id) if id == 0 then return 0 end return id + FONT_BASE end
  function createFont(name, sz) return wrapFont(rawCreate(name, sz)) end
  function loadFont(name) return wrapFont(rawLoad(name)) end
  function textFont(f, sz)
    if math.type(f) == "integer" and f > FONT_BASE then f = f - FONT_BASE end
    return rawTextFont(f, sz)
  end
  local function isFont(n) return math.type(n) == "integer" and n > FONT_BASE and n < FONT_BASE * 2 end

  local Font = {}
  function Font.getSize(f) local s = fontInfo(f) return s end
  function Font.getDefaultSize(f) local s = fontInfo(f) return s > 0 and s or 12 end
  function Font.getName(f) local _, n = fontInfo(f) return n end
  Font.getPostScriptName = Font.getName
  -- ascent / descent / width(c) for a font 1 unit tall: multiply by the size
  function Font.ascent(f) local _, _, a = fontInfo(f) return a end
  function Font.descent(f) local _, _, _, d = fontInfo(f) return d end
  function Font.width(f, c) return charWidth(f, type(c) == "number" and utf8.char(c) or tostring(c)) end
  function Font.kern() return 0 end
  -- getShape("a"): the character's outline as a shape, from the baseline
  local fontOutline = __fontOutline
  __fontOutline = nil
  function Font.getShape(f, c)
    local s = createShape()
    s:beginShape()
    for i, contour in ipairs(fontOutline(f, type(c) == "number" and utf8.char(c) or tostring(c))) do
      if i > 1 then s:beginContour() end
      for _, seg in ipairs(contour) do
        if seg[1] == 0 then s:vertex(seg[2], seg[3])
        elseif seg[1] == 2 then s:quadraticVertex(seg[2], seg[3], seg[4], seg[5])
        else s:bezierVertex(seg[2], seg[3], seg[4], seg[5], seg[6], seg[7]) end
      end
      if i > 1 then s:endContour() end
    end
    s:endShape(CLOSE)
    return s
  end
  function Font.isSmooth() return true end

  -- pixels of each image, counted from 0 like the canvas `pixels`
  local pixelsOf = {}
  local Image = {}
  function Image.loadPixels(img) pixelsOf[img] = loadPx(img, pixelsOf[img]) end
  function Image.updatePixels(img)
    if pixelsOf[img] == nil then error("updatePixels() needs loadPixels() first", 2) end
    updatePx(img, pixelsOf[img])
  end
  -- get(x, y) -> color; get(x, y, w, h) -> a new image; get() -> a copy
  function Image.get(img, x, y, w, h)
    if x == nil then return imageCopy(img) end
    if w ~= nil then return imageGet(img, x, y, w, h) end
    return getPx(img, x, y)
  end
  function Image.set(img, x, y, c)
    imageSet(img, x, y, c)
    if pixelsOf[img] then pixelsOf[img] = nil end
  end
  -- copy() -> a new image; copy(sx, sy, sw, sh, dx, dy, dw, dh) inside this
  -- one; copy(src, sx, sy, sw, sh, dx, dy, dw, dh) from another
  function Image.copy(img, a, ...)
    local n = select("#", ...)
    if a == nil then return imageCopy(img) end
    if n >= 8 then return blendImg(img, a, { ... }, REPLACE) end
    return blendImg(img, img, { a, ... }, REPLACE)
  end
  Image.clone = Image.copy
  -- blend(sx, sy, sw, sh, dx, dy, dw, dh, mode) or blend(src, sx, ..., dh, mode)
  function Image.blend(img, ...)
    local args = { ... }
    local mode = table.remove(args)
    if #args >= 9 then local src = table.remove(args, 1) return blendImg(img, src, args, mode) end
    return blendImg(img, img, args, mode)
  end
  function Image.resize(img, w, h) imageResize(img, w, h or 0) pixelsOf[img] = nil end
  function Image.mask(img, m) pixelsOf[img] = nil return imageMask(img, m) end
  function Image.filter(img, kind, param) filterImg(img, kind, param) pixelsOf[img] = nil end
  function Image.save(img, path) return saveImg(img, path) end
  function Image.isLoaded(img) return size(img) > 0 end

  local mt = debug.getmetatable(0) or {}
  mt.__index = function(n, key)
    if isFont(n) then
      local f = Font[key]
      if f then return f end
    elseif math.type(n) == "integer" then
      if key == "width" then return (size(n)) end
      if key == "height" then local _, h = size(n) return h end
      if key == "pixels" then
        if pixelsOf[n] == nil then pixelsOf[n] = loadPx(n) end
        return pixelsOf[n]
      end
      local f = Image[key]
      if f then return f end
    end
    error("attempt to index a number value", 2)
  end
  mt.__newindex = function(n, key, v)
    if key == "pixels" and math.type(n) == "integer" and not isFont(n) and type(v) == "table" then
      pixelsOf[n] = v
      return
    end
    error("attempt to index a number value", 2)
  end
  debug.setmetatable(0, mt)
end

-- ── getMatrix / setMatrix ─────────────────────────────────────────────────
-- local m = getMatrix()   m.m02 is the x offset   m:translate(10, 0)   setMatrix(m)
-- A PMatrix2D (m00 .. m12) in a 2D sketch, a PMatrix3D (m00 .. m33) after
-- size(w, h, P3D). Methods change the matrix and return it.
do
  local get, set = __getMatrix, __setMatrix
  __getMatrix, __setMatrix = nil, nil
  local names3 = { "m00", "m01", "m02", "m03", "m10", "m11", "m12", "m13",
                   "m20", "m21", "m22", "m23", "m30", "m31", "m32", "m33" }
  local names2 = { "m00", "m01", "m02", "m10", "m11", "m12" }
  local M2, M3 = {}, {}
  M2.__index, M3.__index = M2, M3

  local function new2(a) local m = setmetatable({}, M2) for i, k in ipairs(names2) do m[k] = a[i] end return m end
  local function new3(a) local m = setmetatable({}, M3) for i, k in ipairs(names3) do m[k] = a[i] end return m end
  -- rows of a 3D matrix as a 4 x 4 table, and back
  local function rows(m) local r = {} for i = 0, 3 do r[i] = {} for j = 0, 3 do r[i][j] = m["m" .. i .. j] end end return r end
  local function mul(a, b)
    local r = {}
    for i = 0, 3 do r[i] = {} for j = 0, 3 do
      local s = 0 for k = 0, 3 do s = s + a[i][k] * b[k][j] end r[i][j] = s
    end end
    return r
  end
  local function from(m, r) for i = 0, 3 do for j = 0, 3 do m["m" .. i .. j] = r[i][j] end end return m end
  -- as a 4 x 4 either way
  local function full(m)
    if getmetatable(m) == M2 then
      return { [0] = { [0] = m.m00, m.m01, 0, m.m02 }, { [0] = m.m10, m.m11, 0, m.m12 },
               { [0] = 0, 0, 1, 0 }, { [0] = 0, 0, 0, 1 } }
    end
    return rows(m)
  end
  local function back(m, r)
    if getmetatable(m) == M2 then
      m.m00, m.m01, m.m02, m.m10, m.m11, m.m12 = r[0][0], r[0][1], r[0][3], r[1][0], r[1][1], r[1][3]
      return m
    end
    return from(m, r)
  end
  local function ident() return { [0] = { [0] = 1, 0, 0, 0 }, { [0] = 0, 1, 0, 0 }, { [0] = 0, 0, 1, 0 }, { [0] = 0, 0, 0, 1 } } end
  local function apply(m, r) return back(m, mul(full(m), r)) end
  local function preApply(m, r) return back(m, mul(r, full(m))) end
  -- the other matrix of apply(), as rows: a matrix or 6 / 16 numbers
  local function other(a, ...)
    if type(a) == "table" then return full(a) end
    local v = { a, ... }
    if #v == 6 then return full(new2(v)) end
    return rows(new3(v))
  end

  for _, M in ipairs({ M2, M3 }) do
    local names = M == M2 and names2 or names3
    function M:array() local t = {} for i, k in ipairs(names) do t[i] = self[k] end return t end
    function M:get() local c = setmetatable({}, M) for _, k in ipairs(names) do c[k] = self[k] end return c end
    function M:set(a, ...)
      local v = type(a) == "table" and a:array() or { a, ... }
      if #v ~= #names then v = (M == M2) and { v[1], v[2], v[4], v[5], v[6], v[8] } or v end
      for i, k in ipairs(names) do self[k] = v[i] or self[k] end
      return self
    end
    function M:reset() return back(self, ident()) end
    function M:apply(...) return apply(self, other(...)) end
    function M:preApply(...) return preApply(self, other(...)) end
    function M:translate(x, y, z) local r = ident() r[0][3], r[1][3], r[2][3] = x, y, z or 0 return apply(self, r) end
    function M:scale(x, y, z)
      local r = ident()
      r[0][0], r[1][1], r[2][2] = x, y or x, z or (y == nil and x or 1)
      return apply(self, r)
    end
    function M:rotate(a)
      local r, c, s = ident(), math.cos(a), math.sin(a)
      r[0][0], r[0][1], r[1][0], r[1][1] = c, -s, s, c
      return apply(self, r)
    end
    M.rotateZ = M.rotate
    function M:shearX(a) local r = ident() r[0][1] = math.tan(a) return apply(self, r) end
    function M:shearY(a) local r = ident() r[1][0] = math.tan(a) return apply(self, r) end
    -- mult(v) -> a new PVector: the point moved by the matrix
    function M:mult(v, y, z)
      local x = type(v) == "table" and v.x or v
      if type(v) == "table" then y, z = v.y, v.z end
      local r = full(self)
      z = z or 0
      return createVector(r[0][0] * x + r[0][1] * y + r[0][2] * z + r[0][3],
                          r[1][0] * x + r[1][1] * y + r[1][2] * z + r[1][3],
                          r[2][0] * x + r[2][1] * y + r[2][2] * z + r[2][3])
    end
    function M:multX(x, y, z) return self:mult(x, y, z).x end
    function M:multY(x, y, z) return self:mult(x, y, z).y end
    function M:print() print(tostring(self)) end
    M.__tostring = function(m)
      local r, lines = full(m), {}
      local n = M == M2 and 2 or 4
      for i = 0, n - 1 do
        local row = {}
        for j = 0, (M == M2 and 2 or 3) do
          local col = (M == M2 and j == 2) and 3 or j
          row[#row + 1] = string.format("%10.4f", r[i][col])
        end
        lines[#lines + 1] = table.concat(row, " ")
      end
      return table.concat(lines, "\n")
    end
    M.toString = M.__tostring
  end
  -- determinant / invert for the 2D one
  function M2:determinant() return self.m00 * self.m11 - self.m01 * self.m10 end
  function M2:invert()
    local d = self:determinant()
    if math.abs(d) <= 1e-12 then return false end
    local a, b, c, e, f, g = self.m00, self.m01, self.m02, self.m10, self.m11, self.m12
    self.m00, self.m01, self.m02 = f / d, -b / d, (b * g - f * c) / d
    self.m10, self.m11, self.m12 = -e / d, a / d, (e * c - a * g) / d
    return true
  end
  -- 3D: rotateX / rotateY / rotate(a, x, y, z), transpose, determinant, invert
  function M3:rotateX(a) local r, c, s = ident(), math.cos(a), math.sin(a) r[1][1], r[1][2], r[2][1], r[2][2] = c, -s, s, c return apply(self, r) end
  function M3:rotateY(a) local r, c, s = ident(), math.cos(a), math.sin(a) r[0][0], r[0][2], r[2][0], r[2][2] = c, s, -s, c return apply(self, r) end
  local rotate2 = M3.rotate
  function M3:rotate(a, x, y, z)
    if x == nil then return rotate2(self, a) end
    local len = math.sqrt(x * x + y * y + z * z)
    if len == 0 then return self end
    x, y, z = x / len, y / len, z / len
    local c, s = math.cos(a), math.sin(a)
    local t = 1 - c
    local r = ident()
    r[0][0], r[0][1], r[0][2] = t * x * x + c, t * x * y - s * z, t * x * z + s * y
    r[1][0], r[1][1], r[1][2] = t * x * y + s * z, t * y * y + c, t * y * z - s * x
    r[2][0], r[2][1], r[2][2] = t * x * z - s * y, t * y * z + s * x, t * z * z + c
    return apply(self, r)
  end
  function M3:transpose() local r, t = rows(self), {} for i = 0, 3 do t[i] = {} for j = 0, 3 do t[i][j] = r[j][i] end end return from(self, t) end
  local function det3(a, b, c, d, e, f, g, h, i) return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g) end
  local function minor(r, row, col)
    local v = {}
    for i = 0, 3 do if i ~= row then for j = 0, 3 do if j ~= col then v[#v + 1] = r[i][j] end end end end
    return det3(table.unpack(v))
  end
  function M3:determinant()
    local r, d = rows(self), 0
    for j = 0, 3 do d = d + ((j % 2 == 0) and 1 or -1) * r[0][j] * minor(r, 0, j) end
    return d
  end
  function M3:invert()
    local d = self:determinant()
    if math.abs(d) <= 1e-12 then return false end
    local r, inv = rows(self), {}
    for i = 0, 3 do inv[i] = {} for j = 0, 3 do inv[i][j] = (((i + j) % 2 == 0) and 1 or -1) * minor(r, j, i) / d end end
    from(self, inv)
    return true
  end

  PMatrix2D = setmetatable({}, { __index = M2, __call = function(_, ...)
    local v = { ... }
    if #v == 0 then v = { 1, 0, 0, 0, 1, 0 } elseif type(v[1]) == "table" then v = v[1]:array() end
    return new2(v)
  end })
  PMatrix3D = setmetatable({}, { __index = M3, __call = function(_, ...)
    local v = { ... }
    if #v == 0 then v = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } elseif type(v[1]) == "table" then v = v[1]:array() end
    return new3(v)
  end })

  -- getMatrix() or getMatrix(target): the current transform
  function getMatrix(target)
    local a = get()
    local m
    if is3D() then m = new3(a) else m = new2({ a[1], a[2], a[4], a[5], a[6], a[8] }) end
    if target then return target:set(m:array()) end
    return m
  end
  -- setMatrix(m): the current transform becomes m (a matrix, or 6 / 16 numbers)
  function setMatrix(m, ...)
    if type(m) == "table" then return set(m:array()) end
    return set({ m, ... })
  end
  -- applyMatrix(m), applyMatrix(n00, n01, n02, n10, n11, n12) or 16 numbers,
  -- in Processing's order (row by row)
  local apply3 = applyMatrix
  function applyMatrix(m, ...)
    if type(m) == "table" then return set(m:array(), true) end
    if select("#", ...) == 5 then return set({ m, ... }, true) end
    return apply3(m, ...)
  end
end
