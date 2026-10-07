function setup() size(300, 200) end
function draw() background(0) if frameCount > 400 then exit() end end
function mousePressed() print("mousePressed", mouseX, mouseY, mouseButton, mouseIsPressed) end
function mouseReleased() print("mouseReleased", mouseX, mouseY, mouseButton) end
function mouseClicked() print("mouseClicked") end
function mouseMoved() print("mouseMoved", mouseX, mouseY) end
function mouseDragged() print("mouseDragged", mouseX, mouseY, mouseButton) end
function mouseWheel(d) print("mouseWheel", d) end
function keyPressed() print("keyPressed", key == CODED and "CODED" or ("[" .. key .. "]"), keyCode, keyIsPressed) end
function keyReleased() print("keyReleased", key == CODED and "CODED" or ("[" .. key .. "]"), keyCode) end
function keyTyped() print("keyTyped", "[" .. key .. "]") end
