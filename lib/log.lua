local peripherals = require("lib.peripherals")

local log = {}

log.VERSION = 1
log.MAGIC = "MYLUA_LOG_V1"
log.PROTOCOL = "mylua:log"

local Logger = {}
Logger.__index = Logger

local reservedPayloadFields = {
    magic = true,
    kind = true,
    version = true,
    source = true,
    computerId = true,
    label = true,
    message = true,
    time = true,
    level = true,
    event = true,
    context = true,
    data = true,
    protocol = true,
    nativePrint = true,
    enabled = true,
    reason = true,
    modemName = true,
}

local function valueToString(value)
    if value == nil then
        return "nil"
    end

    return tostring(value)
end

local function currentEpoch()
    if os.epoch then
        return os.epoch("utc")
    end

    if os.time then
        return os.time()
    end

    return nil
end

local function copyFields(target, fields, reserved)
    if type(fields) ~= "table" then
        return
    end

    for key, value in pairs(fields) do
        if type(key) == "string" and value ~= nil and type(value) ~= "function" and not (reserved and reserved[key]) then
            target[key] = value
        end
    end
end

local function hasFields(fields)
    if type(fields) ~= "table" then
        return false
    end

    return next(fields) ~= nil
end

local function resolveContext(context)
    if type(context) == "function" then
        local ok, fields = pcall(context)

        if ok then
            return fields
        end

        return nil
    end

    return context
end

function log.formatValues(...)
    local values = { ... }
    local parts = {}

    for index = 1, #values do
        parts[index] = valueToString(values[index])
    end

    return table.concat(parts, " ")
end

function log.makePayload(message, options, fields)
    options = options or {}
    fields = fields or {}

    local context = {}
    copyFields(context, resolveContext(options.context))
    copyFields(context, resolveContext(fields.context))

    local data = {}
    copyFields(data, fields.data)
    copyFields(data, fields, reservedPayloadFields)

    local payload = {
        magic = log.MAGIC,
        kind = "log",
        version = log.VERSION,
        source = fields.source or options.source,
        computerId = os.getComputerID and os.getComputerID() or nil,
        label = os.getComputerLabel and os.getComputerLabel() or nil,
        message = valueToString(message),
        level = fields.level or options.level or "info",
        event = fields.event or options.event,
        time = currentEpoch(),
    }

    if hasFields(context) then
        payload.context = context
    end

    if hasFields(data) then
        payload.data = data
    end

    return payload
end

function log.isPayload(payload)
    return type(payload) == "table" and
        payload.magic == log.MAGIC and
        payload.kind == "log" and
        payload.version == log.VERSION
end

function log.field(payload, key)
    if type(payload) ~= "table" then
        return nil
    end

    if payload[key] ~= nil then
        return payload[key]
    end

    if type(payload.data) == "table" and payload.data[key] ~= nil then
        return payload.data[key]
    end

    if type(payload.context) == "table" and payload.context[key] ~= nil then
        return payload.context[key]
    end

    return nil
end

function log.sourceFor(sender, payload)
    return log.field(payload, "label") or log.field(payload, "source") or log.field(payload, "computerId") or sender
end

function log.formatPayload(sender, payload)
    local source = log.sourceFor(sender, payload)
    local position = ""
    local level = ""
    local x = log.field(payload, "x")
    local y = log.field(payload, "y")
    local z = log.field(payload, "z")

    if x ~= nil and y ~= nil and z ~= nil then
        position = " @" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
    end

    if log.field(payload, "level") and log.field(payload, "level") ~= "info" then
        level = "[" .. tostring(log.field(payload, "level")):upper() .. "] "
    end

    return level .. tostring(source) .. position .. ": " .. tostring(payload.message or "")
end

function log.receive(timeout, protocol)
    protocol = protocol or log.PROTOCOL

    while true do
        local sender, payload, receivedProtocol

        if timeout ~= nil then
            sender, payload, receivedProtocol = rednet.receive(protocol, timeout)
        else
            sender, payload, receivedProtocol = rednet.receive(protocol)
        end

        if not sender then
            return nil, nil, nil
        end

        if log.isPayload(payload) then
            return sender, payload, receivedProtocol
        end
    end
end

function log.start(options)
    options = options or {}

    local logger = setmetatable({
        enabled = false,
        reason = nil,
        modemName = nil,
        protocol = options.protocol or log.PROTOCOL,
        source = options.source,
        context = options.context,
        nativePrint = options.nativePrint or print,
    }, Logger)

    local modemName, reason = peripherals.openRednet(options)

    if modemName then
        logger.enabled = true
        logger.modemName = modemName
    else
        logger.reason = reason
    end

    return logger
end

function log.open(options)
    return log.start(options)
end

local function withLevel(level, fields)
    local result = {}

    copyFields(result, fields)
    result.level = result.level or level

    return result
end

function Logger:send(message, fields)
    if not self.enabled then
        return false, self.reason
    end

    local payload = log.makePayload(message, self, fields)
    local ok, reason = pcall(rednet.broadcast, payload, self.protocol)

    if not ok then
        return false, tostring(reason)
    end

    return true
end

function Logger:log(level, message, fields)
    message = valueToString(message)

    if self.nativePrint then
        self.nativePrint(message)
    end

    self:send(message, withLevel(level or "info", fields))
    return message
end

function Logger:info(message, fields)
    return self:log("info", message, fields)
end

function Logger:warn(message, fields)
    return self:log("warn", message, fields)
end

function Logger:error(message, fields)
    return self:log("error", message, fields)
end

function Logger:debug(message, fields)
    return self:log("debug", message, fields)
end

function Logger:success(message, fields)
    return self:log("success", message, fields)
end

function Logger:event(event, message, fields, level)
    fields = withLevel(level or "info", fields)
    fields.event = event

    return self:log(fields.level, message or event, fields)
end

function Logger:print(...)
    local message = log.formatValues(...)

    return self:log("info", message)
end

function Logger:wrapPrint(nativePrint)
    if nativePrint then
        self.nativePrint = nativePrint
    end

    return function(...)
        return self:print(...)
    end
end

return log
