local args = { ... }
local items = require("/lib.items")
local log = require("/lib.log")
local nativePrint = print

local DIR_FORWARD = 0
local DIR_RIGHT = 1
local DIR_BACK = 2
local DIR_LEFT = 3

local dx = {
    [DIR_FORWARD] = 0,
    [DIR_RIGHT] = 1,
    [DIR_BACK] = 0,
    [DIR_LEFT] = -1,
}

local dz = {
    [DIR_FORWARD] = 1,
    [DIR_RIGHT] = 0,
    [DIR_BACK] = -1,
    [DIR_LEFT] = 0,
}

local roomWidth = nil
local roomDepth = nil
local roomHeight = nil
local torchSpacing = nil
local x = 0
local y = 0
local z = 0
local facing = DIR_FORWARD
local cellsCleared = 0
local junkDropped = 0
local currentPhase = "init"
local visited = {}

local logger = log.start({
    source = "room",
    nativePrint = nativePrint,
    context = function()
        return {
            x = x,
            y = y,
            z = z,
            facing = facing,
            phase = currentPhase,
            roomWidth = roomWidth,
            roomDepth = roomDepth,
            roomHeight = roomHeight,
            cellsCleared = cellsCleared,
            targetCells = roomWidth and roomDepth and roomHeight and (roomWidth * roomDepth * roomHeight) or nil,
            torchSpacing = torchSpacing,
            junkDropped = junkDropped,
        }
    end,
})

local function print(...)
    nativePrint(...)
end

local function logInfo(event, message, fields)
    fields = fields or {}
    fields.event = event
    logger:info(message, fields)
end

local function logWarn(event, message, fields)
    fields = fields or {}
    fields.event = event
    logger:warn(message, fields)
end

local function logSuccess(event, message, fields)
    fields = fields or {}
    fields.event = event
    logger:success(message, fields)
end

local function readNumber(prompt, default)
    while true do
        if default ~= nil then
            write(prompt .. " [" .. tostring(default) .. "]: ")
        else
            write(prompt .. ": ")
        end

        local input = read()

        if input == "" and default ~= nil then
            return default
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
        logWarn("fuel_wait", context, {
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

local function clearDown()
    while turtle.detectDown() do
        local success, reason = turtle.digDown()

        if not success then
            return false, formatDigReason("below", reason, turtle.inspectDown)
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

local function moveUp()
    while true do
        local success, reason = turtle.up()

        if success then
            y = y + 1
            return true
        end

        if reason == "Out of fuel" then
            waitForFuel(1, "The turtle is out of fuel.")
        elseif turtle.detectUp() then
            local cleared, digReason = clearUp()

            if not cleared then
                return false, digReason
            end
        else
            turtle.attackUp()
            sleep(0.2)
        end
    end
end

local function moveDown()
    while true do
        local success, reason = turtle.down()

        if success then
            y = y - 1
            return true
        end

        if reason == "Out of fuel" then
            waitForFuel(1, "The turtle is out of fuel.")
        elseif turtle.detectDown() then
            local cleared, digReason = clearDown()

            if not cleared then
                return false, digReason
            end
        else
            turtle.attackDown()
            sleep(0.2)
        end
    end
end

local function mustMove(ok, reason)
    if not ok then
        error(reason or "movement failed", 0)
    end
end

local function distanceToHome()
    return math.abs(x) + math.abs(y) + math.abs(z)
end

local function waitForWorkingFuel()
    waitForFuel((distanceToHome() * 2) + 30, "Need enough fuel to keep mining and return to the chest.")
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
                    logWarn("junk_drop_failed", "Could not drop junk", {
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

local function goToY(targetY)
    while y < targetY do
        mustMove(moveUp())
    end

    while y > targetY do
        mustMove(moveDown())
    end
end

local function goToX(targetX)
    if x < targetX then
        turnTo(DIR_RIGHT)

        while x < targetX do
            mustMove(moveForward())
        end
    elseif x > targetX then
        turnTo(DIR_LEFT)

        while x > targetX do
            mustMove(moveForward())
        end
    end
end

local function goToZ(targetZ)
    if z < targetZ then
        turnTo(DIR_FORWARD)

        while z < targetZ do
            mustMove(moveForward())
        end
    elseif z > targetZ then
        turnTo(DIR_BACK)

        while z > targetZ do
            mustMove(moveForward())
        end
    end
end

local function goHome()
    currentPhase = "return_home"
    waitForFuel(distanceToHome() + 10, "Need enough fuel to return to the chest.")

    if z > 0 then
        goToX(0)

        if z > 1 then
            goToZ(1)
        end

        goToY(0)
        goToZ(0)
    else
        goToY(0)
        goToX(0)
    end

    turnTo(DIR_FORWARD)
end

local function returnToPosition(targetX, targetY, targetZ, targetFacing)
    currentPhase = "return_to_work"
    waitForFuel(math.abs(targetX) + math.abs(targetY) + math.abs(targetZ) + 20, "Need enough fuel to return to the room.")

    if targetZ > 0 then
        goToZ(1)
        goToY(targetY)
        goToX(targetX)
        goToZ(targetZ)
    else
        goToY(targetY)
        goToX(targetX)
        goToZ(targetZ)
    end

    turnTo(targetFacing)
end

local function waitForChestBehind()
    turnTo(DIR_BACK)

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
                        logWarn("chest_full", "Chest is full or cannot accept this item.", {
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
    turnTo(DIR_FORWARD)

    logInfo("goods_unload", "Unloaded goods", {
        count = unloaded,
        junkDropped = junkDropped,
        torches = countTorches(),
        emptySlots = emptySlots(),
    })
end

local function serviceAtHome(reason, returnToWork)
    local savedX = x
    local savedY = y
    local savedZ = z
    local savedFacing = facing
    local savedPhase = currentPhase

    print("")
    logInfo("service_start", "Returning to chest", {
        reason = reason,
        returnToWork = returnToWork,
        fuel = fuelLevel(),
    })

    goHome()
    unloadGoodsAtHome()

    if returnToWork then
        returnToPosition(savedX, savedY, savedZ, savedFacing)
        currentPhase = savedPhase
    end
end

local function serviceInventory()
    discardJunk()

    if inventoryNeedsUnload() then
        serviceAtHome("Inventory nearly full.", true)
    end
end

local function ensureTorchSupply()
    if torchSpacing < 1 then
        return false
    end

    if selectTorchSlot() then
        return true
    end

    local savedX = x
    local savedY = y
    local savedZ = z
    local savedFacing = facing
    local savedPhase = currentPhase

    logWarn("torch_missing", "Out of torches.", {
        torches = 0,
    })

    goHome()
    unloadGoodsAtHome()

    while not selectTorchSlot() do
        print("Add torches to the turtle, then press Enter.")
        read()
    end

    returnToPosition(savedX, savedY, savedZ, savedFacing)
    currentPhase = savedPhase
    return true
end

local function isRoomCell(cellX, cellZ, cellY)
    return cellX >= 0 and cellX < roomWidth and cellZ >= 1 and cellZ <= roomDepth and cellY >= 0 and cellY < roomHeight
end

local function visitKey(cellX, cellZ, cellY)
    return tostring(cellX) .. ":" .. tostring(cellZ) .. ":" .. tostring(cellY)
end

local function markCurrentCell()
    if not isRoomCell(x, z, y) then
        return
    end

    local key = visitKey(x, z, y)

    if visited[key] then
        return
    end

    visited[key] = true
    cellsCleared = cellsCleared + 1
end

local function isPerimeterCell()
    return x == 0 or x == roomWidth - 1 or z == 1 or z == roomDepth
end

local function shouldPlaceTorchHere()
    if torchSpacing < 1 or y ~= 0 or not isPerimeterCell() then
        return false
    end

    if cellsCleared == 1 then
        return false
    end

    return cellsCleared % torchSpacing == 0
end

local function faceTorchWall()
    if x == 0 then
        turnTo(DIR_LEFT)
        return true
    elseif x == roomWidth - 1 then
        turnTo(DIR_RIGHT)
        return true
    elseif z == roomDepth then
        turnTo(DIR_FORWARD)
        return true
    elseif z == 1 then
        turnTo(DIR_BACK)
        return true
    end

    return false
end

local function placeTorchIfNeeded()
    if not shouldPlaceTorchHere() then
        return true
    end

    ensureTorchSupply()

    local savedFacing = facing

    if not faceTorchWall() then
        turnTo(savedFacing)
        return true
    end

    local cleared, clearReason = clearForward()
    local placed = false
    local placeReason = clearReason

    if cleared then
        selectTorchSlot()
        placed, placeReason = turtle.place()
    end

    turnTo(savedFacing)

    if placed then
        logInfo("torch_place", "Placed torch", {
            torches = countTorches(),
        })
        return true
    end

    logWarn("torch_place_failed", "Could not place torch", {
        reason = placeReason,
        torches = countTorches(),
    })

    return false, "could not place torch: " .. tostring(placeReason)
end

local function reportProgress(force)
    local targetCells = roomWidth * roomDepth * roomHeight

    if force or cellsCleared % 25 == 0 or cellsCleared >= targetCells then
        logInfo("room_progress", "Room progress", {
            current = cellsCleared,
            total = targetCells,
            roomWidth = roomWidth,
            roomDepth = roomDepth,
            roomHeight = roomHeight,
            junkDropped = junkDropped,
            torches = countTorches(),
            emptySlots = emptySlots(),
        })
    end
end

local function afterArrivingAtCell()
    markCurrentCell()
    discardJunk()

    local torchOk, torchReason = placeTorchIfNeeded()

    if not torchOk then
        return false, torchReason
    end

    serviceInventory()
    reportProgress(false)

    return true
end

local function goToCell(targetX, targetZ, targetY)
    waitForWorkingFuel()
    goToY(targetY)
    goToX(targetX)
    goToZ(targetZ)

    return afterArrivingAtCell()
end

local function sweepLayer(layer)
    currentPhase = "layer_" .. tostring(layer + 1)

    local xStart = 0
    local xEnd = roomWidth - 1
    local xStep = 1

    if layer % 2 == 1 then
        xStart = roomWidth - 1
        xEnd = 0
        xStep = -1
    end

    local column = xStart

    while true do
        local firstZ = 1
        local lastZ = roomDepth
        local zStep = 1

        if z > 1 then
            firstZ = roomDepth
            lastZ = 1
            zStep = -1
        end

        local rowZ = firstZ

        while true do
            local ok, reason = goToCell(column, rowZ, layer)

            if not ok then
                return false, reason
            end

            if rowZ == lastZ then
                break
            end

            rowZ = rowZ + zStep
        end

        if column == xEnd then
            break
        end

        column = column + xStep
    end

    return true
end

local function parsePositiveInteger(value)
    local number = tonumber(value)

    if not number or number ~= math.floor(number) or number < 1 then
        return nil
    end

    return number
end

roomWidth = parsePositiveInteger(args[1])
roomDepth = parsePositiveInteger(args[2])
roomHeight = parsePositiveInteger(args[3])
torchSpacing = tonumber(args[4]) or 8

if not roomWidth then
    roomWidth = readNumber("Room X width", nil)
end

while roomWidth < 1 do
    print("Room X width must be at least 1.")
    roomWidth = readNumber("Room X width", nil)
end

if not roomDepth then
    roomDepth = readNumber("Room Z depth", nil)
end

while roomDepth < 1 do
    print("Room Z depth must be at least 1.")
    roomDepth = readNumber("Room Z depth", nil)
end

if not roomHeight then
    roomHeight = readNumber("Room Y height", nil)
end

while roomHeight < 1 do
    print("Room Y height must be at least 1.")
    roomHeight = readNumber("Room Y height", nil)
end

if args[4] then
    torchSpacing = tonumber(args[4])
else
    torchSpacing = readNumber("Torch spacing, 0 disables torches", 8)
end

while not torchSpacing or torchSpacing ~= math.floor(torchSpacing) or torchSpacing < 0 do
    print("Torch spacing must be a whole number, or 0 to disable torches.")
    torchSpacing = readNumber("Torch spacing, 0 disables torches", 8)
end

print("")
print("Room miner")
print("Room size: " .. roomWidth .. " x " .. roomDepth .. " x " .. roomHeight .. " (x z y)")
print("Torch spacing: " .. (torchSpacing > 0 and ("every " .. torchSpacing .. " cells") or "disabled"))
print("")
print("Start position:")
print("- At the front-left-bottom entrance, just outside the room")
print("- Facing into the room depth (z)")
print("- Chest directly behind the turtle")
print("- Torches in turtle inventory if torch spacing is enabled")
print("- Junk stone will be dropped below the turtle")
print("")

logInfo("room_start", "Room miner configured", {
    roomWidth = roomWidth,
    roomDepth = roomDepth,
    roomHeight = roomHeight,
    targetCells = roomWidth * roomDepth * roomHeight,
    torchSpacing = torchSpacing,
    torches = countTorches(),
})

if not readYesNo("Ready to mine", true) then
    logWarn("cancelled", "Cancelled.", {})
    return
end

if torchSpacing > 0 then
    ensureTorchSupply()
end

waitForFuel(20, "Add starting fuel to the turtle.")

local stopReason = nil

local ran, failure = pcall(function()
    for layer = 0, roomHeight - 1 do
        local ok, reason = sweepLayer(layer)

        if not ok then
            stopReason = reason
            break
        end
    end
end)

if not ran then
    stopReason = tostring(failure)
end

if stopReason then
    logWarn("room_stopped", "Room mining stopped", {
        reason = stopReason,
        current = cellsCleared,
        total = roomWidth * roomDepth * roomHeight,
        junkDropped = junkDropped,
    })
else
    logSuccess("room_complete", "Room complete", {
        current = cellsCleared,
        total = roomWidth * roomDepth * roomHeight,
        roomWidth = roomWidth,
        roomDepth = roomDepth,
        roomHeight = roomHeight,
        junkDropped = junkDropped,
    })
end

serviceAtHome("Room mining finished.", false)

print("")
print("Done.")
print("Room cells cleared: " .. cellsCleared .. "/" .. tostring(roomWidth * roomDepth * roomHeight))

if stopReason then
    print("Reason: " .. stopReason)
end
