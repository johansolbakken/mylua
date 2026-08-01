local peripherals = {}

local function normalizeOptions(options)
    if type(options) == "table" then
        if options.preferredName == nil then
            options.preferredName = options.name or options.modemName or options.monitorName or options.bridgeName
        end

        return options
    end

    if options ~= nil then
        return {
            preferredName = options,
        }
    end

    return {}
end

local function wrapPeripheral(name)
    if not name or not peripheral or not peripheral.wrap then
        return nil
    end

    local ok, wrapped = pcall(peripheral.wrap, name)

    if ok then
        return wrapped
    end

    return nil
end

function peripherals.hasType(name, typeName)
    if not name or not typeName or not peripheral then
        return false
    end

    if peripheral.hasType then
        local ok, result = pcall(peripheral.hasType, name, typeName)

        if ok then
            return result == true
        end
    end

    if not peripheral.getType then
        return false
    end

    local ok, result = pcall(peripheral.getType, name)

    if not ok then
        return false
    end

    if type(result) == "table" then
        for _, value in ipairs(result) do
            if value == typeName then
                return true
            end
        end

        return false
    end

    return result == typeName
end

function peripherals.findPeripheral(typeName, options)
    options = normalizeOptions(options)

    local function accepts(name, wrapped)
        if type(options.filter) ~= "function" then
            return true
        end

        return options.filter(name, wrapped) == true
    end

    if options.preferredName and peripherals.hasType(options.preferredName, typeName) then
        local wrapped = wrapPeripheral(options.preferredName)

        if accepts(options.preferredName, wrapped) then
            return options.preferredName, wrapped
        end
    end

    if options.strictPreferred then
        return nil, nil
    end

    if peripheral and peripheral.find then
        local foundName = nil
        local foundPeripheral = nil
        local ok = pcall(peripheral.find, typeName, function(name, wrapped)
            if not accepts(name, wrapped) then
                return false
            end

            foundName = name
            foundPeripheral = wrapped
            return true
        end)

        if ok and foundName then
            return foundName, foundPeripheral
        end
    end

    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripherals.hasType(name, typeName) then
                local wrapped = wrapPeripheral(name)

                if accepts(name, wrapped) then
                    return name, wrapped
                end
            end
        end
    end

    return nil, nil
end

function peripherals.isWirelessModem(modem)
    if not modem or not modem.isWireless then
        return false
    end

    local ok, wireless = pcall(modem.isWireless)
    return ok and wireless == true
end

function peripherals.findModem(options)
    options = normalizeOptions(options)

    if options.preferWireless == nil then
        options.preferWireless = true
    end

    local function accepts(name, modem)
        if type(options.filter) ~= "function" then
            return true
        end

        return options.filter(name, modem) == true
    end

    if options.preferredName and peripherals.hasType(options.preferredName, "modem") then
        local modem = wrapPeripheral(options.preferredName)

        if accepts(options.preferredName, modem) then
            return options.preferredName, modem
        end
    end

    if options.strictPreferred then
        return nil, nil
    end

    local fallbackName = nil
    local fallbackModem = nil
    local foundName = nil
    local foundModem = nil

    local function consider(name, modem)
        if not accepts(name, modem) then
            return false
        end

        if not fallbackName then
            fallbackName = name
            fallbackModem = modem
        end

        if not options.preferWireless or peripherals.isWirelessModem(modem) then
            foundName = name
            foundModem = modem
            return true
        end

        return false
    end

    if peripheral and peripheral.find then
        pcall(peripheral.find, "modem", consider)
    end

    if not foundName and not fallbackName and peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripherals.hasType(name, "modem") then
                local modem = wrapPeripheral(name)

                if consider(name, modem) then
                    break
                end
            end
        end
    end

    return foundName or fallbackName, foundModem or fallbackModem
end

function peripherals.openRednet(options)
    options = normalizeOptions(options)

    if not rednet or not rednet.open then
        return nil, "rednet unavailable"
    end

    local modemName = peripherals.findModem(options)

    if not modemName then
        return nil, "no modem found"
    end

    if rednet.isOpen and rednet.isOpen(modemName) then
        return modemName
    end

    local ok, reason = pcall(rednet.open, modemName)

    if not ok then
        return nil, tostring(reason)
    end

    if rednet.isOpen and not rednet.isOpen(modemName) then
        return nil, "rednet did not open " .. modemName
    end

    return modemName
end

function peripherals.findMonitor(options)
    return peripherals.findPeripheral("monitor", options)
end

function peripherals.findMeBridge(options)
    local name, bridge = peripherals.findPeripheral("me_bridge", options)

    if bridge then
        return name, bridge
    end

    return peripherals.findPeripheral("meBridge", options)
end

function peripherals.waitForMonitor(options)
    options = normalizeOptions(options)

    while true do
        local monitorName, monitor = peripherals.findMonitor(options)

        if monitor then
            return monitorName, monitor
        end

        if type(options.onMissing) == "function" then
            options.onMissing()
        else
            print(options.waitingMessage or "No monitor found. Attach a monitor.")
        end

        os.pullEvent()
    end
end

function peripherals.waitForMeBridge(options)
    options = normalizeOptions(options)

    while true do
        local bridgeName, bridge = peripherals.findMeBridge(options)

        if bridge then
            return bridgeName, bridge
        end

        if type(options.onMissing) == "function" then
            options.onMissing()
        else
            print(options.waitingMessage or "No ME Bridge found. Attach an Advanced Peripherals ME Bridge.")
        end

        os.pullEvent()
    end
end

return peripherals
