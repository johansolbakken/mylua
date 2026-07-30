local args = { ... }
local log = require("/lib.log")
local render = require("/lib.log_render")
local peripherals = require("/lib.peripherals")

local preferredMonitor = args[1]
local monitorOptions = nil

if preferredMonitor and preferredMonitor ~= "" then
    monitorOptions = {
        monitorName = preferredMonitor,
        strictPreferred = true,
        waitingMessage = "Attach monitor " .. preferredMonitor .. ".",
    }
end

local modemName, modemReason = peripherals.openRednet()

if not modemName then
    error("No modem found for log listener: " .. tostring(modemReason), 0)
end

local monitorName = nil
local monitor = nil
local width = 1
local height = 1
local bodyHeight = 1
local lines = {}

local function configureMonitor()
    pcall(monitor.setTextScale, 0.5)
    monitor.setCursorBlink(false)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    width, height = monitor.getSize()
    bodyHeight = math.max(1, height - 2)
end

local function attachMonitor()
    monitorName, monitor = peripherals.waitForMonitor(monitorOptions)
    configureMonitor()
end

local function clearLine(y)
    monitor.setCursorPos(1, y)
    monitor.write(string.rep(" ", width))
end

local function writeLine(y, text, color)
    clearLine(y)
    monitor.setCursorPos(1, y)
    monitor.setTextColor(color or colors.white)
    monitor.write(tostring(text or ""):sub(1, width))
end

local function draw()
    width, height = monitor.getSize()
    bodyHeight = math.max(1, height - 2)

    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    writeLine(1, "Logs  " .. modemName .. "  " .. monitorName, colors.cyan)
    writeLine(2, log.PROTOCOL .. "  " .. tostring(#lines) .. " rows", colors.gray)

    local start = math.max(1, #lines - bodyHeight + 1)
    local y = 3

    for index = start, #lines do
        if y > height then
            break
        end

        local line = lines[index]
        writeLine(y, line.text, line.color)
        y = y + 1
    end
end

local function pushLine(text, color)
    lines[#lines + 1] = {
        text = tostring(text or ""),
        color = color or colors.white,
    }

    while #lines > 500 do
        table.remove(lines, 1)
    end
end

local function pushWrapped(text, color)
    text = tostring(text or "")

    if width < 1 then
        pushLine(text, color)
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

        pushLine(text:sub(1, cut), color)
        text = text:sub(cut + 1)

        while text:sub(1, 1) == " " do
            text = text:sub(2)
        end
    end

    pushLine(text, color)
end

local function pushPayload(sender, payload)
    for _, row in ipairs(render.rows(sender, payload)) do
        pushWrapped(row.text, row.color)
    end
end

attachMonitor()
pushWrapped("Listening on " .. modemName .. " for " .. log.PROTOCOL, colors.lightGray)
draw()

while true do
    local event, first, second, third = os.pullEvent()

    if event == "rednet_message" then
        local sender = first
        local payload = second
        local protocol = third

        if protocol == log.PROTOCOL and log.isPayload(payload) then
            pushPayload(sender, payload)
            draw()
        end
    elseif event == "monitor_resize" and first == monitorName then
        configureMonitor()
        draw()
    elseif event == "peripheral_detach" and first == monitorName then
        attachMonitor()
        draw()
    end
end
