local args = { ... }
local ae2 = require("/lib.ae2_storage")
local peripherals = require("/lib.peripherals")

local function usage()
    print("Usage: bin/ae2_storage [options]")
    print("  --monitor <name>   Use a specific monitor side/name")
    print("  --bridge <name>    Use a specific ME Bridge side/name")
    print("  --interval <secs>  Refresh interval, default 5")
    print("  --scale <size>     Monitor text scale, default 0.5")
end

local function parseArgs(values)
    local options = {
        interval = 5,
        scale = 0.5,
    }

    local index = 1

    while index <= #values do
        local value = values[index]

        if value == "--help" or value == "-h" then
            options.help = true
        elseif value == "--monitor" or value == "-m" then
            index = index + 1
            options.monitorName = values[index]
        elseif value == "--bridge" or value == "-b" then
            index = index + 1
            options.bridgeName = values[index]
        elseif value == "--interval" or value == "-i" then
            index = index + 1
            options.interval = tonumber(values[index]) or options.interval
        elseif value == "--scale" or value == "-s" then
            index = index + 1
            options.scale = tonumber(values[index]) or options.scale
        elseif options.monitorName == nil then
            options.monitorName = value
        elseif options.bridgeName == nil then
            options.bridgeName = value
        elseif tonumber(value) ~= nil then
            options.interval = tonumber(value)
        end

        index = index + 1
    end

    options.interval = math.max(1, options.interval)

    if options.scale < 0.5 then
        options.scale = 0.5
    elseif options.scale > 5 then
        options.scale = 5
    end

    return options
end

local options = parseArgs(args)

if options.help then
    usage()
    return
end

local monitorOptions = nil
local bridgeOptions = nil

if options.monitorName and options.monitorName ~= "" then
    monitorOptions = {
        preferredName = options.monitorName,
        strictPreferred = true,
    }
end

if options.bridgeName and options.bridgeName ~= "" then
    bridgeOptions = {
        preferredName = options.bridgeName,
        strictPreferred = true,
    }
end

local function truncateText(text, maxWidth)
    text = tostring(text or "")
    maxWidth = math.max(0, maxWidth or 0)

    if #text <= maxWidth then
        return text
    end

    if maxWidth <= 3 then
        return text:sub(1, maxWidth)
    end

    return text:sub(1, maxWidth - 3) .. "..."
end

local function padRight(text, width)
    text = truncateText(text, width)

    if #text < width then
        return text .. string.rep(" ", width - #text)
    end

    return text
end

local function writeLine(screen, width, y, text, textColor, backgroundColor)
    screen.setBackgroundColor(backgroundColor)
    screen.setTextColor(textColor)
    screen.setCursorPos(1, y)
    screen.write(padRight(text, width))
end

local function writeRight(screen, width, y, text, textColor, backgroundColor)
    text = truncateText(text, width)
    screen.setBackgroundColor(backgroundColor)
    screen.setTextColor(textColor)
    screen.setCursorPos(math.max(1, width - #text + 1), y)
    screen.write(text)
end

local function progressColor(percent)
    local _, color = ae2.statusForPercent(percent)
    return color or colors.green
end

local function drawBar(screen, width, y, percent)
    local barWidth = width
    local x = 1

    if width >= 10 then
        barWidth = width - 2
        x = 2
    end

    barWidth = math.max(1, barWidth)

    local filled = math.floor(barWidth * ae2.barPercent(percent) / 100 + 0.5)
    filled = math.max(0, math.min(barWidth, filled))

    screen.setCursorPos(x, y)
    screen.setBackgroundColor(progressColor(percent))
    screen.write(string.rep(" ", filled))

    screen.setBackgroundColor(colors.gray)
    screen.write(string.rep(" ", barWidth - filled))

    screen.setBackgroundColor(colors.black)
end

local function formatPercent(percent)
    return string.format("%.1f%%", tonumber(percent) or 0)
end

local function formatCount(value)
    if value == nil then
        return "?"
    end

    return ae2.formatNumber(value)
end

local function currentTime()
    if textutils and textutils.formatTime and os.time then
        return textutils.formatTime(os.time(), true)
    end

    return ""
end

local function resolveScreen()
    local monitorName, monitor = peripherals.findMonitor(monitorOptions)

    if monitor then
        local ok, currentScale = pcall(monitor.getTextScale)

        if not ok or currentScale ~= options.scale then
            pcall(monitor.setTextScale, options.scale)
        end

        return monitorName, monitor, true
    end

    return "terminal", term, false
end

local lastScreenName = nil
local lastWidth = nil
local lastHeight = nil
local lastBodyBottom = 0

local function configureScreen(screen, screenName, width, height)
    pcall(screen.setCursorBlink, false)
    screen.setBackgroundColor(colors.black)
    screen.setTextColor(colors.white)

    local changed = screenName ~= lastScreenName or width ~= lastWidth or height ~= lastHeight

    if changed then
        screen.clear()

        lastScreenName = screenName
        lastWidth = width
        lastHeight = height
        lastBodyBottom = 0
    end
end

local function clearStaleRows(screen, width, fromY, toY, backgroundColor)
    for y = fromY, toY do
        writeLine(screen, width, y, "", colors.white, backgroundColor)
    end
end

local function finishBody(screen, width, height, nextY, backgroundColor)
    local footerTop = height >= 2 and height - 1 or height + 1
    local clearUntil = math.min(lastBodyBottom, footerTop - 1)

    if nextY <= clearUntil then
        clearStaleRows(screen, width, nextY, clearUntil, backgroundColor)
    end

    lastBodyBottom = math.max(0, math.min(nextY - 1, footerTop - 1))
end

local function drawMissing(screen, width, height, screenName, message)
    local background = colors.black
    local y = 1

    writeLine(screen, width, 1, "AE2 STORAGE", colors.cyan, colors.black)
    y = 2

    if height >= 2 then
        writeLine(screen, width, 2, message, colors.red, colors.black)
        y = 3
    end

    if height >= 4 then
        writeLine(screen, width, 4, "Screen: " .. screenName, colors.lightGray, colors.black)
        y = 5
    end

    if height >= 5 then
        writeLine(screen, width, 5, "Refresh: " .. tostring(options.interval) .. "s", colors.gray, colors.black)
        y = 6
    end

    finishBody(screen, width, height, y, background)
end

local function drawSnapshot(screen, width, height, screenName, bridgeName, snapshot)
    local background = colors.black
    local muted = colors.lightGray
    local dim = colors.gray
    local main = colors.white
    local accent = colors.cyan
    local statusColor = snapshot.statusColor or progressColor(snapshot.percent)
    local y = 1

    writeLine(screen, width, y, "AE2 STORAGE", accent, background)
    writeRight(screen, width, y, snapshot.status, statusColor, background)
    y = y + 1

    if height >= y then
        writeLine(screen, width, y, "Full: " .. formatPercent(snapshot.percent), statusColor, background)
        y = y + 1
    end

    if height >= y then
        drawBar(screen, width, y, snapshot.percent)
        y = y + 1
    end

    if height >= y then
        writeLine(screen, width, y, "Used : " .. ae2.formatBytes(snapshot.usedBytes), main, background)
        y = y + 1
    end

    if height >= y then
        writeLine(screen, width, y, "Free : " .. ae2.formatBytes(snapshot.freeBytes), main, background)
        y = y + 1
    end

    if height >= y then
        writeLine(screen, width, y, "Total: " .. ae2.formatBytes(snapshot.totalBytes), main, background)
        y = y + 1
    end

    if snapshot.itemCount ~= nil and height >= y then
        writeLine(screen, width, y, "Items: " .. formatCount(snapshot.itemCount), muted, background)
        y = y + 1
    end

    if snapshot.typeCount ~= nil and height >= y then
        writeLine(screen, width, y, "Types: " .. tostring(snapshot.typeCount), muted, background)
        y = y + 1
    end

    if #snapshot.topItems > 0 and height >= y + 1 then
        writeLine(screen, width, y, "Top items", accent, background)
        y = y + 1

        for _, item in ipairs(snapshot.topItems) do
            if y >= height then
                break
            end

            writeLine(
                screen,
                width,
                y,
                ae2.formatNumber(item.amount) .. " " .. tostring(item.name),
                muted,
                background
            )
            y = y + 1
        end
    elseif snapshot.itemSummaryReason and height >= y + 1 then
        writeLine(screen, width, y, "Item list unavailable", dim, background)
        y = y + 1
    end

    finishBody(screen, width, height, y, background)

    if height >= 2 then
        writeLine(screen, width, height - 1, "Bridge: " .. tostring(bridgeName), dim, background)
    end

    writeLine(
        screen,
        width,
        height,
        "Screen: " .. tostring(screenName) .. "  " .. currentTime(),
        dim,
        background
    )
end

local function draw()
    local screenName, screen = resolveScreen()
    local width, height = screen.getSize()

    configureScreen(screen, screenName, width, height)

    local bridgeName, bridge = peripherals.findMeBridge(bridgeOptions)

    if not bridge then
        local wanted = options.bridgeName and ("ME Bridge " .. options.bridgeName) or "ME Bridge"
        drawMissing(screen, width, height, screenName, "Missing " .. wanted)
        return
    end

    local snapshot, reason = ae2.readSnapshot(bridge)

    if not snapshot then
        drawMissing(screen, width, height, screenName, tostring(reason))
        return
    end

    drawSnapshot(screen, width, height, screenName, bridgeName, snapshot)
end

while true do
    draw()

    local timer = os.startTimer(options.interval)

    while true do
        local event, first = os.pullEvent()

        if event == "timer" and first == timer then
            break
        elseif event == "monitor_resize" or event == "peripheral" or event == "peripheral_detach" then
            break
        end
    end
end
