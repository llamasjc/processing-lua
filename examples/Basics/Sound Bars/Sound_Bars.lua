-- Talk, whistle or clap: the bars show how much of each pitch the
-- microphone hears, low on the left, high on the right.

local mic, fft, amp
local bars = {}

function setup()
  size(640, 360)
  mic = AudioIn()
  mic:start()
  fft = FFT(64)
  fft:input(mic)
  amp = Amplitude()
  amp:input(mic)
  for i = 1, 64 do bars[i] = 0 end
end

function draw()
  background(18)
  local spectrum = fft:analyze()
  local w = width / 64
  noStroke()
  colorMode(HSB, 360, 100, 100)
  for i = 1, 64 do
    bars[i] = bars[i] + (spectrum[i] - bars[i]) * 0.3
    local h = math.min(bars[i] * 8, 1) * (height - 40)
    fill(i * 4, 70, 95)
    rect((i - 1) * w, height - h, w - 2, h)
  end
  colorMode(RGB, 255)
  fill(255, 60)
  circle(width / 2, 80, 20 + amp:analyze() * 400)
end
