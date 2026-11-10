-- shapes cover the ones drawn before them, solid or see-through, in any batch
-- stdout: ok
local function near(a, b) return math.abs(a - b) <= 6 end
function setup() size(250, 50) noLoop() end
function draw()
  background(255) noStroke()
  -- solid then see-through, see-through then solid, both see-through
  local combos = { {255, 255}, {255, 128}, {128, 255}, {128, 128} }
  for i, c in ipairs(combos) do
    local x = (i - 1) * 50
    fill(255, 0, 0, c[1]) rect(x + 5, 5, 30, 30)
    fill(0, 0, 255, c[2]) rect(x + 15, 15, 30, 30)
  end
  -- two solid shapes with a see-through one between them (another batch)
  fill(255, 0, 0) rect(205, 5, 30, 30)
  fill(0, 255, 0, 100) rect(245, 0, 4, 4)
  fill(0, 0, 255) rect(215, 15, 30, 30)
  local want = { {0, 0, 255}, {127, 0, 128}, {0, 0, 255}, {127, 63, 191}, {0, 0, 255} }
  for i, w in ipairs(want) do
    local r, g, b = get((i - 1) * 50 + 25, 25)
    assert(near(r, w[1]) and near(g, w[2]) and near(b, w[3]),
      "overlap " .. i .. ": " .. r .. "," .. g .. "," .. b)
  end
  print("ok") exit()
end
