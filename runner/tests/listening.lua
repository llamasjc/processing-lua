-- stdout: amp 0.0 fft 64 wave 128
-- stdout: errors ok ok
function setup()
  local mic = AudioIn()
  mic:start()
  local amp = Amplitude() amp:input(mic)
  local fft = FFT(64) fft:input(mic)
  local wave = Waveform(128) wave:input(mic)
  fft:analyze() wave:analyze()
  print("amp " .. string.format("%.1f", amp:analyze()) .. " fft " .. #fft.spectrum .. " wave " .. #wave.data)
  local a = pcall(function() Amplitude():analyze() end)
  local b = pcall(function() FFT(8):input(42) end)
  print("errors " .. (a and "no" or "ok") .. " " .. (b and "no" or "ok"))
  mic:stop()
  exit()
end
