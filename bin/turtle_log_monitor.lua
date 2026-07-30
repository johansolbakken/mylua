local log = require("lib.log")
local peripherals = require("lib.peripherals")

local modemName, modemReason = peripherals.openRednet()

if not modemName then
    error("No modem found for log listener: " .. tostring(modemReason), 0)
end

local monitorName, monitor = peripherals.waitForMonitor()

pcall(monitor.setTextScale, 0.5)
monitor.setCursorBlink(false)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

local width, height = monitor.getSize()
local bodyHeight = math.max(1, height - 2)
local lines = {}

local function clearLine(y)
    monitor.setCursorPos(1, y)
    monitor.write(string.rep(" ", width))
end

local function writeLine(y, text, color)
    clearLine(y)
    monitor.setCursorPos(1, y)
    monitor.setTextColor(color or colors.white)
    monitor.write(text:sub(1, width))
end

local function draw()
    width, height = monitor.getSize()
    bodyHeight = math.max(1, height - 2)

    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    writeLine(1, "Logs  " .. modemName .. "  " .. monitorName, colors.cyan)
    writeLine(2, "Protocol " .. log.PROTOCOL, colors.gray)

    local start = math.max(1, #lines - bodyHeight + 1)
    local y = 3

    for index = start, #lines do
        if y > height then
            break
        end

        writeLine(y, lines[index], colors.white)
        y = y + 1
    end
end

local function pushLine(text)
    lines[#lines + 1] = text

    while #lines > 500 do
        table.remove(lines, 1)
    end
end

local function wrapText(text)
    text = tostring(text or "")

    if width < 1 then
        pushLine(text)
        return
    end

    while #text > width do
        local cut = width

        for index = width, 1, -1 do
            if text:sub(index, index) == " " then
                cut = index - 1
                break
            end
        end

        if cut < 1 then
            cut = width
        end

        pushLine(text:sub(1, cut))
        text = text:sub(cut + 1)

        while text:sub(1, 1) == " " do
            text = text:sub(2)
        end
    end

    pushLine(text)
end

wrapText("Listening on " .. modemName .. " for " .. log.PROTOCOL)
draw()

while true do
    local sender, payload = log.receive()

    if sender then
        wrapText(log.formatPayload(sender, payload))
        draw()
    end
end
