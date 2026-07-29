local LOG_MAGIC = "MYLUA_TURTLE_LOG_V1"
local LOG_PROTOCOL = "mylua:turtle_log"

local function findModem()
    local fallback = nil
    local found = nil

    peripheral.find("modem", function(name, modem)
        if not fallback then
            fallback = name
        end

        if modem and modem.isWireless then
            local ok, wireless = pcall(modem.isWireless)

            if ok and wireless then
                found = name
                return true
            end
        end

        return false
    end)

    return found or fallback
end

local function findMonitor()
    local monitorName = nil
    local monitor = peripheral.find("monitor", function(name)
        monitorName = name
        return true
    end)

    return monitorName, monitor
end

local modemName = findModem()

if not modemName then
    error("No modem found", 0)
end

rednet.open(modemName)

local monitorName, monitor = findMonitor()

if not monitor then
    error("No monitor found", 0)
end

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
    writeLine(1, "Turtle logs  " .. modemName .. "  " .. monitorName, colors.cyan)
    writeLine(2, "Magic " .. LOG_MAGIC, colors.gray)

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

local function formatPayload(sender, payload)
    local source = payload.label or payload.computerId or sender
    local position = ""

    if payload.x and payload.y and payload.z then
        position = " @" .. tostring(payload.x) .. "," .. tostring(payload.y) .. "," .. tostring(payload.z)
    end

    return tostring(source) .. position .. ": " .. tostring(payload.message or "")
end

wrapText("Listening on " .. modemName .. " for " .. LOG_PROTOCOL)
draw()

while true do
    local sender, payload = rednet.receive(LOG_PROTOCOL)

    if type(payload) == "table" and payload.magic == LOG_MAGIC and payload.kind == "log" then
        wrapText(formatPayload(sender, payload))
        draw()
    end
end
