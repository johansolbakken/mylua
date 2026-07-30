local args = { ... }
local items = require("/lib.items")
local log = require("/lib.log")
local nativePrint = print

local DIR_EAST = 0
local DIR_SOUTH = 1
local DIR_WEST = 2
local DIR_NORTH = 3

local dx = {
    [DIR_EAST] = 1,
    [DIR_SOUTH] = 0,
    [DIR_WEST] = -1,
    [DIR_NORTH] = 0,
}

local dz = {
    [DIR_EAST] = 0,
    [DIR_SOUTH] = 1,
    [DIR_WEST] = 0,
    [DIR_NORTH] = -1,
}

local x = 0
local y = 0
local z = 0
local facing = DIR_EAST
local mined = 0
local junkDropped = 0
local targetLength = nil
local torchSpacing = nil

local logger = log.start({
    source = "horizontal_miner",
    nativePrint = nativePrint,
    context = function()
        return {
            x = x,
            y = y,
            z = z,
            facing = facing,
            distance = mined,
            junkDropped = junkDropped,
            targetLength = targetLength,
            torchSpacing = torchSpacing,
            status = "mining",
        }
    end,
})

local function print(...)
    nativePrint(...)
end

local function readNumber(prompt, default, allowBlank)
    while true do
        if default ~= nil then
            write(prompt .. " [" .. tostring(default) .. "]: ")
        else
            write(prompt .. ": ")
        end

        local input = read()

        if input == "" then
            if allowBlank then
                return nil
            end

            if default ~= nil then
                return default
            end
        end

        local number = tonumber(input)

        if number and number == math.floor(number) then
            return number
        end

        print("Enter a whole number.")
    end
end

local function readYesNo(prompt, default)
    while true do
        local suffix = " [y/n]: "

        if default == true then
            suffix = " [Y/n]: "
        elseif default == false then
            suffix = " [y/N]: "
        end

        write(prompt .. suffix)
        local input = string.lower(read())

        if input == "" and default ~= nil then
            return default
        end

        if input == "y" or input == "yes" then
            return true
        end

        if input == "n" or input == "no" then
            return false
        end

        print("Answer y or n.")
    end
end

local function fuelIsUnlimited()
    return turtle.getFuelLevel() == "unlimited"
end

local function fuelLevel()
    if fuelIsUnlimited() then
        return math.huge
    end

    return turtle.getFuelLevel()
end

local function tryRefuelTo(required)
    if fuelIsUnlimited() then
        return
    end

    local selected = turtle.getSelectedSlot()

    for slot = 1, 16 do
        if fuelLevel() >= required then
            break
        end

        turtle.select(slot)

        while turtle.getItemCount(slot) > 0 and turtle.refuel(0) and fuelLevel() < required do
            if not turtle.refuel(1) then
                break
            end
        end
    end

    turtle.select(selected)
end

local function waitForFuel(required, context)
    if fuelIsUnlimited() then
        return
    end

    tryRefuelTo(required)

    while fuelLevel() < required do
        print("")
        logger:warn(context, {
            event = "fuel_wait",
            fuel = fuelLevel(),
            required = required,
        })
        print("Fuel: " .. tostring(fuelLevel()) .. ", need at least " .. tostring(required) .. ".")
        print("Add fuel to the turtle, then press Enter.")
        read()
        tryRefuelTo(required)
    end
end

local function blockName(inspect)
    local ok, data = inspect()

    if ok and data and data.name then
        return data.name
    end

    return "unknown block"
end

local function formatDigReason(direction, reason, inspect)
    return "blocked " .. direction .. " by " .. blockName(inspect) .. " (" .. tostring(reason) .. ")"
end

local function clearForward()
    while turtle.detect() do
        local success, reason = turtle.dig()

        if not success then
            return false, formatDigReason("forward", reason, turtle.inspect)
        end

        sleep(0)
    end

    return true
end

local function clearUp()
    while turtle.detectUp() do
        local success, reason = turtle.digUp()

        if not success then
            return false, formatDigReason("above", reason, turtle.inspectUp)
        end

        sleep(0)
    end

    return true
end

local function turnLeft()
    turtle.turnLeft()
    facing = (facing + 3) % 4
end

local function turnRight()
    turtle.turnRight()
    facing = (facing + 1) % 4
end

local function turnAround()
    turnRight()
    turnRight()
end

local function turnTo(direction)
    local difference = (direction - facing) % 4

    if difference == 1 then
        turnRight()
    elseif difference == 2 then
        turnAround()
    elseif difference == 3 then
        turnLeft()
    end
end

local function moveForward()
    while true do
        local success, reason = turtle.forward()

        if success then
            x = x + dx[facing]
            z = z + dz[facing]
            return true
        end

        if reason == "Out of fuel" then
            waitForFuel(1, "The turtle is out of fuel.")
        elseif turtle.detect() then
            local cleared, digReason = clearForward()

            if not cleared then
                return false, digReason
            end
        else
            turtle.attack()
            sleep(0.2)
        end
    end
end

local function mustMove(ok, reason)
    if not ok then
        error(reason or "movement failed", 0)
    end
end

local function emptySlots()
    local count = 0

    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end

    return count
end

local function inventoryNeedsUnload()
    return emptySlots() <= 1
end

local function selectTorchSlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot, true)

            if items.isTorch(detail) then
                turtle.select(slot)
                return true
            end
        end
    end

    return false
end

local function countTorches()
    local count = 0

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot, true)

            if items.isTorch(detail) then
                count = count + turtle.getItemCount(slot)
            end
        end
    end

    return count
end

local function discardJunk()
    local selected = turtle.getSelectedSlot()
    local dropped = 0

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot, true)

            if items.isJunk(detail) then
                local count = turtle.getItemCount(slot)
                turtle.select(slot)

                if turtle.dropDown() then
                    dropped = dropped + count
                    junkDropped = junkDropped + count
                else
                    logger:warn("Could not drop junk", {
                        event = "junk_drop_failed",
                        item = detail.name,
                        count = count,
                    })
                end
            end
        end
    end

    turtle.select(selected)

    return dropped
end

local function goHome()
    waitForFuel(math.abs(x) + 2, "Need enough fuel to return to the chest.")
    turnTo(DIR_WEST)

    while x > 0 do
        mustMove(moveForward())
    end

    turnTo(DIR_EAST)
end

local function returnToDistance(distance)
    waitForFuel(distance + 2, "Need enough fuel to return to the mining face.")
    turnTo(DIR_EAST)

    while x < distance do
        mustMove(moveForward())
    end

    turnTo(DIR_EAST)
end

local function waitForChestBehind()
    turnTo(DIR_WEST)

    while not turtle.detect() do
        print("No chest or inventory behind the start position.")
        print("Place one behind the turtle, then press Enter.")
        read()
    end
end

local function unloadGoodsAtHome()
    discardJunk()
    waitForChestBehind()

    local unloaded = 0

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot, true)

            if items.isGoods(detail) then
                turtle.select(slot)

                while turtle.getItemCount(slot) > 0 do
                    local count = turtle.getItemCount(slot)

                    if turtle.drop() then
                        unloaded = unloaded + count
                    else
                        logger:warn("Chest is full or cannot accept this item.", {
                            event = "chest_full",
                            item = detail.name,
                            count = count,
                        })
                        print("Empty/fix the chest, then press Enter.")
                        read()
                    end
                end
            end
        end
    end

    turtle.select(1)
    turnTo(DIR_EAST)

    logger:info("Unloaded goods", {
        event = "goods_unload",
        count = unloaded,
        junkDropped = junkDropped,
        torches = countTorches(),
        emptySlots = emptySlots(),
    })
end

local function serviceAtHome(reason, returnToWork)
    local savedDistance = x

    print("")
    logger:info("Returning to chest", {
        event = "service_start",
        reason = reason,
        returnToWork = returnToWork,
        distance = savedDistance,
        fuel = fuelLevel(),
    })

    goHome()
    unloadGoodsAtHome()

    if returnToWork then
        waitForFuel(savedDistance * 2 + 20, "Need more fuel before returning to the tunnel.")
        logger:info("Returning to mining face", {
            event = "service_return",
            distance = savedDistance,
            fuel = fuelLevel(),
        })
        returnToDistance(savedDistance)
    end
end

local function serviceInventory()
    discardJunk()

    if inventoryNeedsUnload() then
        serviceAtHome("Inventory nearly full.", true)
    end
end

local function ensureTorchSupply()
    if selectTorchSlot() then
        return true
    end

    local savedDistance = x

    logger:warn("Out of torches.", {
        event = "torch_missing",
        torches = 0,
        distance = savedDistance,
    })
    goHome()
    unloadGoodsAtHome()

    while not selectTorchSlot() do
        print("Add torches to the turtle, then press Enter.")
        read()
    end

    waitForFuel(savedDistance * 2 + 20, "Need more fuel before returning to the tunnel.")
    returnToDistance(savedDistance)
    return true
end

local function tryPlaceTorchOnSide(side)
    if side == "right" then
        turnRight()
    else
        turnLeft()
    end

    local cleared = true
    local reason = nil

    if turtle.detect() then
        cleared, reason = clearForward()
    end

    local placed = false
    local placeReason = reason

    if cleared then
        selectTorchSlot()
        placed, placeReason = turtle.place()
    end

    if side == "right" then
        turnLeft()
    else
        turnRight()
    end

    return placed, placeReason
end

local function placeTorchIfNeeded()
    if torchSpacing < 1 or mined == 0 or mined % torchSpacing ~= 0 then
        return true
    end

    ensureTorchSupply()

    local selected = turtle.getSelectedSlot()
    local placed, reason = tryPlaceTorchOnSide("right")

    if not placed then
        placed, reason = tryPlaceTorchOnSide("left")
    end

    turtle.select(selected)

    if placed then
        logger:info("Placed torch", {
            event = "torch_place",
            distance = mined,
            torches = countTorches(),
        })
        return true
    else
        logger:warn("Could not place torch", {
            event = "torch_place_failed",
            reason = reason,
            torches = countTorches(),
        })
        return false, "could not place torch: " .. tostring(reason)
    end
end

local function mineStep()
    waitForFuel((x * 2) + 20, "Need enough fuel to mine and return to the chest.")

    local cleared, reason = clearForward()

    if not cleared then
        return false, reason
    end

    local moved, moveReason = moveForward()

    if not moved then
        return false, moveReason
    end

    cleared, reason = clearUp()

    if not cleared then
        return false, reason
    end

    mined = x
    discardJunk()
    local torchOk, torchReason = placeTorchIfNeeded()

    if not torchOk then
        return false, torchReason
    end

    serviceInventory()

    if mined % 10 == 0 or (targetLength and mined >= targetLength) then
        logger:info("Tunnel progress", {
            event = "tunnel_progress",
            current = mined,
            total = targetLength,
            distance = mined,
            junkDropped = junkDropped,
            torches = countTorches(),
            emptySlots = emptySlots(),
        })
    end

    return true
end

local function parseLength(value)
    if value == "forever" or value == "infinite" or value == "inf" then
        return nil
    end

    return tonumber(value)
end

targetLength = parseLength(args[1])
torchSpacing = tonumber(args[2]) or 8

if args[1] and not targetLength and args[1] ~= "forever" and args[1] ~= "infinite" and args[1] ~= "inf" then
    print("Invalid tunnel length: " .. tostring(args[1]))
    targetLength = readNumber("Tunnel length, blank for forever", nil, true)
end

if not args[1] then
    targetLength = readNumber("Tunnel length, blank for forever", nil, true)
end

while targetLength ~= nil and targetLength < 1 do
    print("Tunnel length must be at least 1.")
    targetLength = readNumber("Tunnel length, blank for forever", nil, true)
end

if not args[2] then
    torchSpacing = readNumber("Torch spacing", 8, false)
end

while torchSpacing < 1 do
    print("Torch spacing must be at least 1.")
    torchSpacing = readNumber("Torch spacing", 8, false)
end

print("")
print("Horizontal goods miner")

if targetLength then
    print("Tunnel length: " .. targetLength)
else
    print("Tunnel length: forever/until stopped")
end

print("Tunnel shape: 1 wide x 2 high")
print("Torch spacing: every " .. torchSpacing .. " blocks")
print("")
print("Start position:")
print("- Facing the direction to mine")
print("- Chest directly behind the turtle")
print("- Torches in turtle inventory")
print("- Junk stone will be dropped below the turtle")
print("")

logger:info("Horizontal miner configured", {
    event = "horizontal_miner_start",
    targetLength = targetLength,
    torchSpacing = torchSpacing,
    torches = countTorches(),
})

if not readYesNo("Ready to mine", true) then
    logger:warn("Cancelled.", {
        event = "cancelled",
    })
    return
end

if torchSpacing > 0 then
    ensureTorchSupply()
end

waitForFuel(20, "Add starting fuel to the turtle.")

local stopReason = nil

while targetLength == nil or mined < targetLength do
    local ok, reason = mineStep()

    if not ok then
        stopReason = reason
        break
    end
end

if stopReason then
    logger:warn("Mining stopped", {
        event = "mine_stopped",
        reason = stopReason,
        distance = mined,
        junkDropped = junkDropped,
        targetLength = targetLength,
    })
else
    logger:success("Target tunnel length reached", {
        event = "mine_complete",
        current = mined,
        total = targetLength,
        distance = mined,
        junkDropped = junkDropped,
    })
end

serviceAtHome("Mining finished.", false)

print("")
print("Done.")
print("Tunnel length mined: " .. mined)

if stopReason then
    print("Reason: " .. stopReason)
end
