local args = { ... }

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

local function tryRefuelFromInventory()
    if fuelIsUnlimited() then
        return
    end

    local selected = turtle.getSelectedSlot()

    for slot = 1, 16 do
        turtle.select(slot)

        if turtle.getItemCount(slot) > 0 and turtle.refuel(0) then
            turtle.refuel()
        end
    end

    turtle.select(selected)
end

local function waitForFuel(required, context)
    if fuelIsUnlimited() then
        return
    end

    tryRefuelFromInventory()

    while fuelLevel() < required do
        print("")
        print(context)
        print("Fuel: " .. tostring(fuelLevel()) .. ", need at least " .. tostring(required) .. ".")
        print("Add fuel to the turtle, then press Enter.")
        read()
        tryRefuelFromInventory()
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
            waitForFuel(1, "The turtle is out of fuel where it stands.")
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

local function moveDown()
    while true do
        local success, reason = turtle.down()

        if success then
            y = y + 1
            return true
        end

        if reason == "Out of fuel" then
            waitForFuel(1, "The turtle is out of fuel where it stands.")
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

local function moveUp()
    while true do
        local success, reason = turtle.up()

        if success then
            y = y - 1
            return true
        end

        if reason == "Out of fuel" then
            waitForFuel(1, "The turtle is out of fuel where it stands.")
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

local function mustMove(ok, reason)
    if not ok then
        error(reason or "movement failed", 0)
    end
end

local function moveBackward()
    turnAround()
    mustMove(moveForward())
    turnAround()
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

local function distanceToHome()
    return math.abs(x) + math.abs(z) + y
end

local function moveToDepth(targetY)
    while y > targetY do
        mustMove(moveUp())
    end

    while y < targetY do
        mustMove(moveDown())
    end
end

local function moveToX(targetX)
    if x < targetX then
        turnTo(DIR_EAST)
    elseif x > targetX then
        turnTo(DIR_WEST)
    end

    while x ~= targetX do
        mustMove(moveForward())
    end
end

local function moveToZ(targetZ)
    if z < targetZ then
        turnTo(DIR_SOUTH)
    elseif z > targetZ then
        turnTo(DIR_NORTH)
    end

    while z ~= targetZ do
        mustMove(moveForward())
    end
end

local function goHomeByCoordinates()
    waitForFuel(distanceToHome() + 2, "Need enough fuel to return to the starting chest.")

    moveToDepth(0)
    moveToZ(0)
    moveToX(0)
    turnTo(DIR_EAST)
end

local function goToPosition(position)
    moveToDepth(0)
    moveToX(position.x)
    moveToZ(position.z)
    moveToDepth(position.y)
    turnTo(position.facing)
end

local function waitForChestBehind()
    turnTo(DIR_WEST)

    while not turtle.detect() do
        print("No chest or inventory behind the start position.")
        print("Place one behind the turtle, then press Enter.")
        read()
    end
end

local function unloadAtHome()
    turnTo(DIR_EAST)
    tryRefuelFromInventory()
    waitForChestBehind()

    for slot = 1, 16 do
        turtle.select(slot)

        while turtle.getItemCount(slot) > 0 do
            if not turtle.drop() then
                print("Chest is full or cannot accept this item.")
                print("Empty/fix the chest, then press Enter.")
                read()
            end
        end
    end

    turtle.select(1)
    turnTo(DIR_EAST)
end

local function serviceByCoordinates(reason, returnToWork)
    local position = {
        x = x,
        y = y,
        z = z,
        facing = facing,
    }

    print("")
    print(reason)
    print("Returning to chest...")
    goHomeByCoordinates()
    unloadAtHome()

    if returnToWork then
        local required = (math.abs(position.x) + math.abs(position.z) + position.y) * 2 + 30
        waitForFuel(required, "Need more fuel before returning to the dig.")
        print("Returning to work...")
        goToPosition(position)
    end
end

local shaftWidth = tonumber(args[1])
local requestedDepth = tonumber(args[2])

if not shaftWidth then
    shaftWidth = readNumber("Shaft diameter/width in blocks (even)", 8, false)
end

while shaftWidth < 2 or shaftWidth % 2 ~= 0 do
    print("Use an even shaft diameter, such as 6, 8, 10, or 12.")
    shaftWidth = readNumber("Shaft diameter/width in blocks (even)", 8, false)
end

if args[2] == "bedrock" then
    requestedDepth = nil
elseif not requestedDepth then
    requestedDepth = readNumber("Depth to dig, blank for bedrock", nil, true)
end

while requestedDepth ~= nil and requestedDepth < 1 do
    print("Depth must be at least 1.")
    requestedDepth = readNumber("Depth to dig, blank for bedrock", nil, true)
end

local outerWidth = shaftWidth + 4
local sideLength = outerWidth - 1
local shaftOffset = 2

print("")
print("Square shaft staircase")
print("Shaft diameter: " .. shaftWidth)
print("Outer width: " .. outerWidth)

if requestedDepth then
    print("Target depth: " .. requestedDepth)
else
    print("Target depth: until bedrock/undiggable block")
end

print("")
print("Start position:")
print("- Northwest outside corner")
print("- Facing east")
print("- Chest directly behind")
print("- Shaft begins two blocks forward and two blocks right")
print("")

if not readYesNo("Ready to start", true) then
    print("Cancelled.")
    return
end

waitForFuel(20, "Add starting fuel to the turtle.")

local advanceStairsTo

local function maybeServiceShaft()
    if inventoryNeedsUnload() then
        serviceByCoordinates("Inventory nearly full.", true)
    elseif fuelLevel() < distanceToHome() + 30 then
        serviceByCoordinates("Fuel is low.", true)
    end
end

local function mineShaftLayer()
    for row = 1, shaftWidth do
        for column = 1, shaftWidth do
            maybeServiceShaft()

            local cleared, reason = clearDown()

            if not cleared then
                return false, reason
            end

            if column < shaftWidth then
                mustMove(moveForward())
            end
        end

        if row < shaftWidth then
            if row % 2 == 1 then
                turnRight()
                mustMove(moveForward())
                turnRight()
            else
                turnLeft()
                mustMove(moveForward())
                turnLeft()
            end
        end
    end

    turnRight()

    for _ = 1, shaftWidth - 1 do
        mustMove(moveForward())
    end

    turnRight()

    return true
end

local function mineCentralShaft()
    print("")
    print("Mining shaft with live staircase updates")

    moveToX(shaftOffset)
    moveToZ(shaftOffset)
    turnTo(DIR_EAST)

    local completedDepth = 0
    local stopReason = nil

    while requestedDepth == nil or completedDepth < requestedDepth do
        print("Mining shaft layer " .. tostring(completedDepth + 1) .. "...")

        local ok, reason = mineShaftLayer()

        if not ok then
            stopReason = reason
            break
        end

        completedDepth = completedDepth + 1
        print("Central shaft depth: " .. completedDepth)

        serviceByCoordinates("Unloading shaft layer " .. completedDepth .. ".", false)

        local stairsOk, stairsReason = advanceStairsTo(completedDepth)

        if not stairsOk then
            stopReason = "staircase stopped: " .. tostring(stairsReason)
            break
        end

        if requestedDepth ~= nil and completedDepth >= requestedDepth then
            break
        end

        goToPosition({
            x = shaftOffset,
            y = completedDepth,
            z = shaftOffset,
            facing = DIR_EAST,
        })
    end

    if x ~= 0 or y ~= 0 or z ~= 0 then
        serviceByCoordinates("Central shaft phase finished.", false)
    end

    return completedDepth, stopReason
end

local stairActions = {}
local stairStepsDone = 0
local stairsInitialized = false
local stairPerimeter = sideLength * 4

local function stairPositionForStep(stepNumber)
    local index = (stepNumber - 1) % stairPerimeter
    local side = math.floor(index / sideLength) + 1
    local offset = (index % sideLength) + 1

    return side, offset
end

local function stairReturnCost()
    local cost = 0

    for _, action in ipairs(stairActions) do
        if action == "step" then
            cost = cost + 2
        end
    end

    return cost
end

local function returnHomeByStairs()
    waitForFuel(stairReturnCost() + 2, "Need enough fuel to climb back to the chest.")

    for index = #stairActions, 1, -1 do
        local action = stairActions[index]

        if action == "right" then
            turnLeft()
        elseif action == "step" then
            mustMove(moveUp())
            moveBackward()
        end
    end
end

local function replayStairs()
    for _, action in ipairs(stairActions) do
        if action == "right" then
            turnRight()
        elseif action == "step" then
            mustMove(moveForward())
            mustMove(moveDown())
        end
    end
end

local function serviceByStairs(reason, returnToWork)
    print("")
    print(reason)
    print("Returning to chest...")
    returnHomeByStairs()
    unloadAtHome()

    if returnToWork then
        waitForFuel(stairReturnCost() * 2 + 40, "Need more fuel before descending again.")
        print("Returning to staircase...")
        replayStairs()
    end
end

local function maybeServiceStairs()
    if inventoryNeedsUnload() then
        serviceByStairs("Inventory nearly full.", true)
    elseif fuelLevel() < stairReturnCost() + 30 then
        serviceByStairs("Fuel is low.", true)
    end
end

local function clearInnerLane()
    turnRight()

    local cleared, reason = clearForward()

    if not cleared then
        turnLeft()
        return false, reason
    end

    local moved, moveReason = moveForward()

    if not moved then
        turnLeft()
        return false, moveReason
    end

    cleared, reason = clearUp()

    if not cleared then
        moveBackward()
        turnLeft()
        return false, reason
    end

    moveBackward()
    turnLeft()
    return true
end

local function ensureStairsInitialized()
    if stairsInitialized then
        return true
    end

    local cleared, reason = clearUp()

    if not cleared then
        return false, reason
    end

    cleared, reason = clearInnerLane()

    if not cleared then
        return false, reason
    end

    stairsInitialized = true
    return true
end

local function stairStep()
    local cleared, reason = clearForward()

    if not cleared then
        return false, reason
    end

    local moved, moveReason = moveForward()

    if not moved then
        return false, moveReason
    end

    cleared, reason = clearDown()

    if not cleared then
        moveBackward()
        return false, reason
    end

    moved, moveReason = moveDown()

    if not moved then
        moveBackward()
        return false, moveReason
    end

    stairActions[#stairActions + 1] = "step"

    cleared, reason = clearUp()

    if not cleared then
        return false, reason
    end

    return clearInnerLane()
end

local function turnForNextStairStep()
    if stairStepsDone > 0 and stairStepsDone % sideLength == 0 then
        turnRight()
        stairActions[#stairActions + 1] = "right"
    end
end

advanceStairsTo = function(targetDepth)
    if targetDepth <= stairStepsDone then
        return true
    end

    print("")
    print("Extending staircase to depth " .. targetDepth .. "...")
    turnTo(DIR_EAST)

    local ready, reason = ensureStairsInitialized()

    if not ready then
        return false, reason
    end

    replayStairs()

    while stairStepsDone < targetDepth do
        maybeServiceStairs()
        turnForNextStairStep()

        local nextStep = stairStepsDone + 1
        local side, offset = stairPositionForStep(nextStep)
        local ok, stepReason = stairStep()

        if not ok then
            serviceByStairs("Staircase stopped before catching up.", false)
            return false, stepReason
        end

        stairStepsDone = nextStep
        print("Stair depth: " .. stairStepsDone .. "/" .. targetDepth ..
            " (side " .. side .. ", offset " .. offset .. ")")
    end

    serviceByStairs("Staircase caught up to shaft depth.", false)
    return true
end

local completedShaftDepth, shaftStopReason = mineCentralShaft()

if completedShaftDepth <= 0 then
    print("")
    print("Stopped before any usable shaft depth was completed.")

    if shaftStopReason then
        print("Reason: " .. shaftStopReason)
    end

    return
end

print("")
print("Done.")
print("Central shaft depth: " .. completedShaftDepth)
print("Staircase depth: " .. stairStepsDone)

if shaftStopReason then
    print("Shaft stopped at bedrock/blocked block: " .. shaftStopReason)
end
