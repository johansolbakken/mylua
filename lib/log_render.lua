local log = require("lib.log")

local render = {}

local hiddenKeys = {
    computerId = true,
    context = true,
    data = true,
    kind = true,
    label = true,
    level = true,
    magic = true,
    message = true,
    source = true,
    time = true,
    version = true,
}

local function color(name)
    if colors then
        return colors[name]
    end

    return nil
end

function render.colorForLevel(level)
    level = tostring(level or "info"):lower()

    if level == "error" then
        return color("red")
    elseif level == "warn" or level == "warning" then
        return color("yellow")
    elseif level == "debug" then
        return color("gray")
    elseif level == "success" then
        return color("lime")
    end

    return color("white")
end

function render.detailColor()
    return color("lightGray") or color("gray")
end

local function valueToString(value)
    if value == nil then
        return nil
    end

    if type(value) ~= "table" then
        return tostring(value)
    end

    local keys = {}

    for key in pairs(value) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    local parts = {}

    for index = 1, math.min(#keys, 4) do
        local key = keys[index]
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value[key])
    end

    if #keys > 4 then
        parts[#parts + 1] = "..."
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

local function shortItemName(name)
    if type(name) ~= "string" then
        return valueToString(name)
    end

    return name:match(":(.+)$") or name
end

function render.position(payload)
    local x = log.field(payload, "x")
    local y = log.field(payload, "y")
    local z = log.field(payload, "z")

    if x == nil or y == nil or z == nil then
        return nil
    end

    return "@" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function addPart(parts, used, key, label, value, formatter)
    if value == nil then
        return
    end

    used[key] = true

    if formatter then
        value = formatter(value)
    else
        value = valueToString(value)
    end

    if value and value ~= "" then
        parts[#parts + 1] = label .. "=" .. value
    end
end

local function addProgress(parts, used, payload)
    local progress = log.field(payload, "progress")

    if progress ~= nil then
        addPart(parts, used, "progress", "progress", progress)
        return
    end

    local current = log.field(payload, "current") or log.field(payload, "completedDepth") or log.field(payload, "stairDepth") or log.field(payload, "depth")
    local total = log.field(payload, "total") or log.field(payload, "targetDepth") or log.field(payload, "requestedDepth")

    if current == nil and total == nil then
        return
    end

    used.current = true
    used.completedDepth = true
    used.stairDepth = true
    used.depth = true
    used.total = true
    used.targetDepth = true
    used.requestedDepth = true

    if total ~= nil then
        parts[#parts + 1] = "progress=" .. tostring(current or "?") .. "/" .. tostring(total)
    else
        parts[#parts + 1] = "progress=" .. tostring(current)
    end
end

local function addFuel(parts, used, payload)
    local fuel = log.field(payload, "fuel") or log.field(payload, "fuelLevel")
    local required = log.field(payload, "fuelRequired") or log.field(payload, "required")

    if fuel == nil and required == nil then
        return
    end

    used.fuel = true
    used.fuelLevel = true
    used.fuelRequired = true
    used.required = true

    if required ~= nil then
        parts[#parts + 1] = "fuel=" .. tostring(fuel or "?") .. "/" .. tostring(required)
    else
        parts[#parts + 1] = "fuel=" .. tostring(fuel)
    end
end

local function collectUnknown(parts, used, fields)
    if type(fields) ~= "table" then
        return
    end

    local keys = {}

    for key in pairs(fields) do
        if type(key) == "string" and not used[key] and not hiddenKeys[key] then
            keys[#keys + 1] = key
        end
    end

    table.sort(keys)

    for _, key in ipairs(keys) do
        addPart(parts, used, key, key, fields[key])
    end
end

function render.header(sender, payload)
    local level = tostring(log.field(payload, "level") or "info"):upper()
    local source = tostring(log.sourceFor(sender, payload) or "?")
    local message = tostring(log.field(payload, "message") or "")
    local state = log.field(payload, "phase") or log.field(payload, "status") or log.field(payload, "event")
    local position = render.position(payload)
    local parts = {
        level,
        source,
    }

    if position then
        parts[#parts + 1] = position
    end

    if state then
        parts[#parts + 1] = "[" .. tostring(state) .. "]"
    end

    return table.concat(parts, " ") .. ": " .. message
end

function render.details(payload)
    local parts = {}
    local used = {
        x = true,
        y = true,
        z = true,
    }

    addPart(parts, used, "event", "event", log.field(payload, "event"))
    addPart(parts, used, "phase", "phase", log.field(payload, "phase"))
    addPart(parts, used, "status", "status", log.field(payload, "status"))
    addPart(parts, used, "facing", "facing", log.field(payload, "facing"))
    addFuel(parts, used, payload)
    addProgress(parts, used, payload)
    addPart(parts, used, "distance", "distance", log.field(payload, "distance"))
    addPart(parts, used, "shaftWidth", "shaft", log.field(payload, "shaftWidth"))
    addPart(parts, used, "batchSize", "batch", log.field(payload, "batchSize"))
    addPart(parts, used, "side", "side", log.field(payload, "side"))
    addPart(parts, used, "offset", "offset", log.field(payload, "offset"))
    addPart(parts, used, "slot", "slot", log.field(payload, "slot"))
    addPart(parts, used, "count", "count", log.field(payload, "count"))
    addPart(parts, used, "item", "item", log.field(payload, "item") or log.field(payload, "itemName"), shortItemName)
    used.itemName = true
    addPart(parts, used, "decision", "decision", log.field(payload, "decision"))
    addPart(parts, used, "output", "output", log.field(payload, "output"))
    addPart(parts, used, "returnToWork", "return", log.field(payload, "returnToWork"))
    addPart(parts, used, "reason", "reason", log.field(payload, "reason"))

    collectUnknown(parts, used, payload.data)
    collectUnknown(parts, used, payload.context)

    return table.concat(parts, " ")
end

function render.rows(sender, payload)
    local rows = {
        {
            text = render.header(sender, payload),
            color = render.colorForLevel(log.field(payload, "level")),
        },
    }

    local details = render.details(payload)

    if details ~= "" then
        rows[#rows + 1] = {
            text = "  " .. details,
            color = render.detailColor(),
        }
    end

    return rows
end

return render
