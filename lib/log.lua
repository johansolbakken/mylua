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
    message = true,
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

local function copyPayloadFields(payload, fields)
    if type(fields) ~= "table" then
        return
    end

    for key, value in pairs(fields) do
        if type(key) == "string" and not reservedPayloadFields[key] and value ~= nil then
            payload[key] = value
        end
    end
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

    local payload = {
        magic = log.MAGIC,
        kind = "log",
        version = log.VERSION,
        source = options.source,
        computerId = os.getComputerID and os.getComputerID() or nil,
        label = os.getComputerLabel and os.getComputerLabel() or nil,
        message = valueToString(message),
        time = currentEpoch(),
    }

    copyPayloadFields(payload, resolveContext(options.context))
    copyPayloadFields(payload, fields)

    return payload
end

function log.isPayload(payload)
    return type(payload) == "table" and
        payload.magic == log.MAGIC and
        payload.kind == "log" and
        payload.version == log.VERSION
end

function log.formatPayload(sender, payload)
    local source = payload.label or payload.source or payload.computerId or sender
    local position = ""
    local level = ""

    if payload.x ~= nil and payload.y ~= nil and payload.z ~= nil then
        position = " @" .. tostring(payload.x) .. "," .. tostring(payload.y) .. "," .. tostring(payload.z)
    end

    if payload.level and payload.level ~= "info" then
        level = "[" .. tostring(payload.level):upper() .. "] "
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

function Logger:print(...)
    local message = log.formatValues(...)

    if self.nativePrint then
        self.nativePrint(message)
    end

    self:send(message)
    return message
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
