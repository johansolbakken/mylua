local monitor = peripheral.wrap("back")

if not monitor then
    error("No monitor found on the back")
end

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local width, height = monitor.getSize()

local function centered(text, y, textColor, backgroundColor)
    monitor.setBackgroundColor(backgroundColor or colors.black)
    monitor.setTextColor(textColor or colors.white)

    local x = math.floor((width - #text) / 2) + 1
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

monitor.setBackgroundColor(colors.black)
monitor.clear()

if monitor.isColor() then
    centered("====================", 2, colors.gray)
    centered("STORAGE SYSTEM", 4, colors.cyan)
    centered("BACKEND ROOM", 6, colors.white)
    centered("MAINTENANCE AREA", 8, colors.yellow)
    centered("AUTHORIZED STAFF", 10, colors.lightGray)
    centered("====================", 12, colors.gray)
else
    centered("====================", 2)
    centered("STORAGE SYSTEM", 4)
    centered("BACKEND ROOM", 6)
    centered("MAINTENANCE AREA", 8)
    centered("AUTHORIZED STAFF", 10)
    centered("====================", 12)
end
