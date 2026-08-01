local ae2 = {}

ae2.TOTAL_ITEM_STORAGE_METHODS = {
    "getTotalItemStorage",
    "getMaxItemStorage",
}

ae2.USED_ITEM_STORAGE_METHODS = {
    "getUsedItemStorage",
}

ae2.FREE_ITEM_STORAGE_METHODS = {
    "getAvailableItemStorage",
    "getFreeItemStorage",
}

local function color(name)
    if colors then
        return colors[name]
    end

    return nil
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or 0

    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

local function numberOrNil(value)
    local number = tonumber(value)

    if number == nil then
        return nil
    end

    return number
end

function ae2.callFirst(target, names, ...)
    local errors = {}
    local attempted = false

    for _, name in ipairs(names) do
        local method = target and target[name]

        if type(method) == "function" then
            attempted = true

            local ok, result = pcall(method, ...)

            if ok then
                return result, name
            end

            errors[#errors + 1] = name .. ": " .. tostring(result)
        end
    end

    if attempted then
        return nil, nil, table.concat(errors, "; ")
    end

    return nil, nil, "missing " .. table.concat(names, " or ")
end

local function readNumber(target, names)
    local value, methodName, reason = ae2.callFirst(target, names)
    local number = numberOrNil(value)

    if number ~= nil then
        return number, methodName
    end

    if value ~= nil then
        return nil, methodName, methodName .. " returned non-number " .. tostring(value)
    end

    return nil, methodName, reason
end

function ae2.formatNumber(value)
    value = tonumber(value) or 0

    local sign = ""

    if value < 0 then
        sign = "-"
        value = -value
    end

    local units = {
        "",
        "K",
        "M",
        "G",
        "T",
        "P",
    }
    local unit = 1

    while value >= 1000 and unit < #units do
        value = value / 1000
        unit = unit + 1
    end

    if unit == 1 then
        return sign .. tostring(math.floor(value + 0.5))
    end

    return string.format("%s%.1f%s", sign, value, units[unit])
end

function ae2.formatBytes(value)
    return ae2.formatNumber(value) .. " bytes"
end

function ae2.statusForPercent(percent)
    percent = tonumber(percent) or 0

    if percent >= 95 then
        return "CRITICAL", color("red")
    elseif percent >= 85 then
        return "HIGH", color("orange")
    elseif percent >= 70 then
        return "WATCH", color("yellow")
    end

    return "OK", color("green")
end

function ae2.barPercent(percent)
    return clamp(percent, 0, 100)
end

function ae2.shortItemName(name)
    if type(name) ~= "string" then
        return tostring(name or "?")
    end

    return name:match(":(.+)$") or name
end

local function summarizeItems(items)
    local typeCount = 0
    local itemCount = 0
    local topItems = {}

    for key, item in pairs(items) do
        local name = nil
        local amount = nil

        if type(item) == "table" then
            name = item.displayName or item.name or item.fingerprint or key
            amount = numberOrNil(item.amount or item.count or item.size)
        elseif type(item) == "number" then
            name = key
            amount = item
        end

        if name ~= nil or amount ~= nil then
            typeCount = typeCount + 1
        end

        if amount ~= nil then
            itemCount = itemCount + amount
            topItems[#topItems + 1] = {
                name = ae2.shortItemName(name),
                amount = amount,
            }
        end
    end

    table.sort(topItems, function(left, right)
        return left.amount > right.amount
    end)

    while #topItems > 5 do
        table.remove(topItems)
    end

    return {
        typeCount = typeCount,
        itemCount = itemCount,
        topItems = topItems,
    }
end

local function readItemSummary(bridge)
    local items, methodName, reason = ae2.callFirst(
        bridge,
        {
            "listItems",
        },
        {} -- Empty filter means all stored items.
    )

    if type(items) == "table" then
        local summary = summarizeItems(items)
        summary.methodName = methodName
        return summary
    end

    return {
        reason = reason or "listItems returned no item table",
    }
end

function ae2.readSnapshot(bridge)
    if type(bridge) ~= "table" then
        return nil, "ME Bridge is unavailable"
    end

    local used, usedMethod, usedReason = readNumber(bridge, ae2.USED_ITEM_STORAGE_METHODS)

    if used == nil then
        return nil, "could not read used item storage: " .. tostring(usedReason)
    end

    local total, totalMethod, totalReason = readNumber(bridge, ae2.TOTAL_ITEM_STORAGE_METHODS)

    if total == nil then
        return nil, "could not read total item storage: " .. tostring(totalReason)
    end

    local free, freeMethod = readNumber(bridge, ae2.FREE_ITEM_STORAGE_METHODS)

    if free == nil then
        free = math.max(0, total - used)
        freeMethod = "calculated"
    end

    local percent = 0

    if total > 0 then
        percent = used / total * 100
    end

    local itemSummary = readItemSummary(bridge)
    local status, statusColor = ae2.statusForPercent(percent)

    return {
        usedBytes = used,
        totalBytes = total,
        freeBytes = free,
        percent = percent,
        status = status,
        statusColor = statusColor,
        barPercent = ae2.barPercent(percent),
        usedMethod = usedMethod,
        totalMethod = totalMethod,
        freeMethod = freeMethod,
        typeCount = itemSummary.typeCount,
        itemCount = itemSummary.itemCount,
        topItems = itemSummary.topItems or {},
        itemSummaryReason = itemSummary.reason,
    }
end

return ae2
