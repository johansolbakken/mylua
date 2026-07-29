local args = { ... }

local STATE_PATH = "room_sign.state"
local VERSION = 1

local scales = {
    5,
    4.5,
    4,
    3.5,
    3,
    2.5,
    2,
    1.5,
    1,
    0.5,
}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function joinArgs(startIndex)
    local parts = {}

    for index = startIndex, #args do
        parts[#parts + 1] = args[index]
    end

    return trim(table.concat(parts, " "))
end

local function currentEpoch()
    if os.epoch then
        return os.epoch("utc")
    end

    return nil
end

local function loadState()
    if not fs.exists(STATE_PATH) then
        return {}
    end

    local file = fs.open(STATE_PATH, "r")

    if not file then
        return {}
    end

    local contents = file.readAll()
    file.close()

    local state = textutils.unserialize(contents)

    if type(state) ~= "table" then
        return {}
    end

    return state
end

local function saveState(state)
    state.version = VERSION
    state.updatedAt = currentEpoch()

    local temporaryPath = STATE_PATH .. ".tmp"
    local file = fs.open(temporaryPath, "w")

    if not file then
        error("Cannot write " .. temporaryPath, 0)
    end

    file.write(textutils.serialize(state))
    file.close()

    if fs.exists(STATE_PATH) then
        fs.delete(STATE_PATH)
    end

    fs.move(temporaryPath, STATE_PATH)
end

local function preferredMonitorIsAvailable(name)
    if not name or not peripheral.isPresent or not peripheral.getType then
        return false
    end

    if not peripheral.isPresent(name) then
        return false
    end

    return peripheral.getType(name) == "monitor"
end

local function findMonitor(preferredName)
    if preferredMonitorIsAvailable(preferredName) then
        return preferredName, peripheral.wrap(preferredName)
    end

    local monitorName = nil
    local monitor = peripheral.find("monitor", function(name)
        monitorName = name
        return true
    end)

    return monitorName, monitor
end

local function waitForMonitor(preferredName)
    while true do
        local monitorName, monitor = findMonitor(preferredName)

        if monitor then
            return monitorName, monitor
        end

        print("No monitor found. Attach a monitor.")
        os.pullEvent()
    end
end

local function setColors(monitor, textColor, backgroundColor)
    if backgroundColor then
        monitor.setBackgroundColor(backgroundColor)
    end

    if textColor then
        monitor.setTextColor(textColor)
    end
end

local function clear(monitor, backgroundColor)
    monitor.setCursorBlink(false)
    monitor.setBackgroundColor(backgroundColor)
    monitor.clear()
end

local function normalizeDisplayText(text)
    return trim(text):gsub("%s+", " "):upper()
end

local function wrapText(text, maxWidth)
    maxWidth = math.max(1, maxWidth)

    local lines = {}
    local current = ""

    for rawWord in text:gmatch("%S+") do
        local word = rawWord

        while #word > maxWidth do
            if current ~= "" then
                lines[#lines + 1] = current
                current = ""
            end

            lines[#lines + 1] = word:sub(1, maxWidth)
            word = word:sub(maxWidth + 1)
        end

        if current == "" then
            current = word
        elseif #current + 1 + #word <= maxWidth then
            current = current .. " " .. word
        else
            lines[#lines + 1] = current
            current = word
        end
    end

    if current ~= "" then
        lines[#lines + 1] = current
    end

    if #lines == 0 then
        lines[1] = ""
    end

    return lines
end

local function truncateText(text, maxWidth)
    if #text <= maxWidth then
        return text
    end

    if maxWidth <= 3 then
        return text:sub(1, maxWidth)
    end

    return text:sub(1, maxWidth - 3) .. "..."
end

local function fitLines(lines, maxLines, maxWidth)
    local fitted = {}

    for index = 1, math.min(#lines, maxLines) do
        fitted[index] = truncateText(lines[index], maxWidth)
    end

    if #lines > maxLines and maxLines > 0 then
        fitted[maxLines] = truncateText(lines[maxLines] .. "...", maxWidth)
    end

    return fitted
end

local function layoutFor(monitor, roomName)
    local text = normalizeDisplayText(roomName)
    local fallback = nil

    for _, scale in ipairs(scales) do
        pcall(monitor.setTextScale, scale)

        local width, height = monitor.getSize()
        local border = width >= 8 and height >= 4
        local header = width >= 10 and height >= 6
        local padding = border and 2 or 0
        local usableWidth = math.max(1, width - padding * 2)
        local usableHeight = height

        if border then
            usableHeight = usableHeight - 2
        end

        if header then
            usableHeight = usableHeight - 2
        end

        usableHeight = math.max(1, usableHeight)

        local lines = wrapText(text, usableWidth)
        local layout = {
            scale = scale,
            width = width,
            height = height,
            border = border,
            header = header,
            padding = padding,
            usableWidth = usableWidth,
            usableHeight = usableHeight,
            lines = lines,
        }

        fallback = layout

        if #lines <= usableHeight then
            return layout
        end
    end

    fallback.lines = fitLines(fallback.lines, fallback.usableHeight, fallback.usableWidth)
    return fallback
end

local function writeAt(monitor, x, y, text, textColor, backgroundColor)
    setColors(monitor, textColor, backgroundColor)
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function writeCentered(monitor, y, text, width, textColor, backgroundColor)
    text = truncateText(text, width)
    local x = math.floor((width - #text) / 2) + 1
    writeAt(monitor, math.max(1, x), y, text, textColor, backgroundColor)
end

local function drawBorder(monitor, width, height, color, backgroundColor)
    if width < 2 or height < 2 then
        return
    end

    local horizontal = string.rep("-", math.max(0, width - 2))

    writeAt(monitor, 1, 1, "+" .. horizontal .. "+", color, backgroundColor)

    for y = 2, height - 1 do
        writeAt(monitor, 1, y, "|", color, backgroundColor)
        writeAt(monitor, width, y, "|", color, backgroundColor)
    end

    writeAt(monitor, 1, height, "+" .. horizontal .. "+", color, backgroundColor)
end

local function drawSign(monitor, roomName)
    local layout = layoutFor(monitor, roomName)
    local background = colors.black
    local accent = colors.cyan
    local main = colors.white
    local muted = colors.lightGray

    pcall(monitor.setTextScale, layout.scale)
    clear(monitor, background)

    if layout.border then
        drawBorder(monitor, layout.width, layout.height, accent, background)
    end

    if layout.header then
        writeCentered(monitor, 2, "ROOM", layout.width, muted, background)
    end

    local top = 1
    local bottom = layout.height

    if layout.border then
        top = top + 1
        bottom = bottom - 1
    end

    if layout.header then
        top = top + 2
    end

    local availableHeight = math.max(1, bottom - top + 1)
    local lines = fitLines(layout.lines, availableHeight, layout.usableWidth)
    local startY = top + math.floor((availableHeight - #lines) / 2)

    for index, line in ipairs(lines) do
        writeCentered(monitor, startY + index - 1, line, layout.width, main, background)
    end
end

local state = loadState()
local command = args[1]

if command == "reset" or command == "clear" then
    if fs.exists(STATE_PATH) then
        fs.delete(STATE_PATH)
    end

    print("Deleted " .. STATE_PATH)
    return
end

local roomName = nil

if command == "set" or command == "name" then
    roomName = joinArgs(2)
elseif #args > 0 then
    roomName = joinArgs(1)
end

if roomName == nil or roomName == "" then
    roomName = trim(state.roomName)
end

if roomName == "" then
    write("Room name: ")
    roomName = trim(read())
end

if roomName == "" then
    error("Room name is required", 0)
end

state.roomName = roomName
saveState(state)

local monitorName, monitor = waitForMonitor(state.monitorName)
state.monitorName = monitorName
saveState(state)

print("Room sign: " .. roomName)
print("Monitor: " .. monitorName)

drawSign(monitor, roomName)

while true do
    local event, name = os.pullEvent()

    if event == "monitor_resize" and name == monitorName then
        drawSign(monitor, roomName)
    elseif event == "peripheral_detach" and name == monitorName then
        monitorName, monitor = waitForMonitor(nil)
        state.monitorName = monitorName
        saveState(state)
        drawSign(monitor, roomName)
    elseif event == "peripheral" then
        local newName, newMonitor = findMonitor(monitorName)

        if newMonitor then
            monitorName = newName
            monitor = newMonitor
            state.monitorName = monitorName
            saveState(state)
            drawSign(monitor, roomName)
        end
    end
end
