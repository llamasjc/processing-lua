-- Showcase: a tour of what Lua Mode can draw.
-- Move the mouse, click to stamp a ring, press any key to clear the layer.

local layer, font
local clicks = 0

function setup()
  size(720, 420)
  layer = createGraphics(720, 420)
  -- any installed font; 0 means none was found and text stays in the pixel font
  font = createFont("DejaVu Sans", 22)
end

function draw()
  background(24, 26, 38)

  -- line ends: ROUND, SQUARE, PROJECT
  stroke(120, 180, 255) strokeWeight(14)
  strokeCap(ROUND)   line(40, 50, 180, 50)
  strokeCap(SQUARE)  line(40, 85, 180, 85)
  strokeCap(PROJECT) line(40, 120, 180, 120)

  -- corners: MITER, BEVEL, ROUND
  fill(90, 200, 140) strokeWeight(10)
  strokeJoin(MITER) triangle(230, 130, 270, 40, 310, 130)
  strokeJoin(BEVEL) triangle(340, 130, 380, 40, 420, 130)
  strokeJoin(ROUND) triangle(450, 130, 490, 40, 530, 130)
  strokeJoin(MITER)

  -- arcs: plain, OPEN, CHORD, PIE
  stroke(255) strokeWeight(3) fill(255, 150, 40)
  arc(80, 220, 90, 90, 0, 4.5)
  arc(190, 220, 90, 90, 0, 4.5, OPEN)
  arc(300, 220, 90, 90, 0, 4.5, CHORD)
  arc(410, 220, 90, 90, 0, 4.5, PIE)

  -- a color value, a vector, and a shape that turns
  local spin = createVector(1, 0):rotate(frameCount * 0.02)
  noStroke() rectMode(CENTER)
  push()
  translate(620, 90) rotate(spin:heading()) shearX(0.35)
  fill(lerpColor(color(200, 80, 200), color(80, 200, 220), (sin(frameCount * 0.02) + 1) / 2))
  rect(0, 0, 90, 60)
  pop()
  rectMode(CORNER)

  -- a blend mode that brightens what is under it
  blendMode(ADD) fill(0, 90, 200)
  ellipse(mouseX, mouseY, 110, 110)
  blendMode(BLEND)

  -- an off-screen layer: dots collect on it, and it is drawn over everything
  layer:beginDraw()
  layer:noStroke() layer:fill(255, 220, 60, 90)
  layer:ellipse(mouseX, mouseY, 12, 12)
  layer:endDraw()
  image(layer, 0, 0)

  -- text in a real font, turned a little, with the local time
  textFont(font) fill(255)
  push()
  translate(30, 330) rotate(-0.03)
  text(nf(hour(), 2) .. ":" .. nf(minute(), 2) .. ":" .. nf(second(), 2) ..
       "   clicks: " .. clicks .. "   fps: " .. nf(frameRate, 1, 0), 0, 0)
  pop()
  textFont(0) textSize(16) fill(160, 170, 190)
  text("pixel font: click stamps a ring, any key clears", 30, 370)
end

function mousePressed()
  clicks = clicks + 1
  layer:beginDraw()
  layer:stroke(255, 80, 80) layer:strokeWeight(3) layer:noFill()
  layer:ellipse(mouseX, mouseY, 40, 40)
  layer:endDraw()
end

function keyPressed()
  layer:beginDraw()
  clear()
  layer:endDraw()
end
