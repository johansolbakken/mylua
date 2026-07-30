local monitor = peripheral.wrap("back")

if not monitor then
    error("No monitor found on the back")
end

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)
monitor.setBackgroundColor(colors.black)
monitor.clear()

local width, height = monitor.getSize()

local lines = {
    { "STORAGE SYSTEM", colors.cyan },
    { "BACKEND ROOM", colors.white },
    { "MAINTENANCE AREA", colors.yellow },
    { "AUTHORIZED STAFF ONLY", colors.lightGray },
}

local startY = math.floor((height - #lines) / 2) + 1

for index, line in ipairs(lines) do
    local text = line[1]
    local color = line[2]

    local x = math.floor((width - #text) / 2) + 1
    local y = startY + index - 1

    monitor.setCursorPos(x, y)
    monitor.setTextColor(color)
    monitor.write(text)
end
