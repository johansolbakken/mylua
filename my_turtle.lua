local args = { ... }

local DIR_EAST = 0
local DIR_SOUTH = 1
local DIR_WEST = 2
local DIR_NORTH = 3
local STAIR_TUNNEL_HEIGHT = 4
local WORKSPACE_HEADROOM = 3
local WORKSPACE_TUNNEL_HEIGHT = WORKSPACE_HEADROOM + 1

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
local STATE_PATH = "my_turtle.state"
local LOG_MAGIC = "MYLUA_TURTLE_LOG_V1"
local LOG_PROTOCOL = "mylua:turtle_log"
local nativePrint = print
local logModemName = nil
local logBroadcastEnabled = false
local resumeMode = args[1] == "resume" or args[1] == "--resume" or args[1] == "continue"
local recoverMode = args[1] == "recover" or args[1] == "--recover" or args[1] == "scan"
local stateStatus = "stopped"
local currentPhase = "init"
local shaftWidth = nil
local requestedDepth = nil
local batchSize = 5
local outerWidth = nil
local sideLength = nil
local shaftOffset = 2
local completedDepth = 0
local stairActions = {}
local stairStepsDone = 0
local stairSideIndex = 1
local stairSideMovesDone = 0
local stairPathProgress = 0
local stairsInitialized = false
local stateLoaded = false
local saveState

local function valueToString(value)
    if value == nil then
        return "nil"
    end

    return tostring(value)
end

local function findLogModem()
    if not peripheral or not peripheral.find then
        return nil
    end

    local fallback = nil
    local found = nil

    peripheral.find("modem", function(name, modem)
        if not fallback then
            fallback = name
        end

        if modem and modem.isWireless then
            local ok, wireless = pcall(modem.isWireless)

            if ok and wireless then
                found = name
                return true
            end
        end

        return false
    end)

    return found or fallback
end

local function enableLogBroadcast()
    if not rednet or not rednet.open then
        return false
    end

    logModemName = findLogModem()

    if not logModemName then
        return false
    end

    local ok = pcall(rednet.open, logModemName)

    if not ok then
        return false
    end

    if rednet.isOpen and not rednet.isOpen(logModemName) then
        return false
    end

    logBroadcastEnabled = true
    return true
end

local function broadcastLogMessage(message)
    if not logBroadcastEnabled then
        return
    end

    local payload = {
        magic = LOG_MAGIC,
        kind = "log",
        computerId = os.getComputerID and os.getComputerID() or nil,
        label = os.getComputerLabel and os.getComputerLabel() or nil,
        message = message,
        x = x,
        y = y,
        z = z,
        facing = facing,
        time = os.time and os.time() or nil,
    }

    pcall(rednet.broadcast, payload, LOG_PROTOCOL)
end

local function print(...)
    local values = { ... }
    local parts = {}

    for index = 1, #values do
        parts[index] = valueToString(values[index])
    end

    local message = table.concat(parts, " ")

    nativePrint(message)
    broadcastLogMessage(message)
end

if enableLogBroadcast() then
    print("Log broadcast enabled on modem: " .. logModemName)
else
    nativePrint("Log broadcast disabled: no modem found")
end

local function copyList(list)
    local result = {}

    if type(list) ~= "table" then
        return result
    end

    for index, value in ipairs(list) do
        result[index] = value
    end

    return result
end

local function writeStateFile(state)
    local serialized = textutils.serialize(state)
    local temporaryPath = STATE_PATH .. ".tmp"
    local file = fs.open(temporaryPath, "w")

    if not file then
        error("Cannot write " .. temporaryPath, 0)
    end

    file.write(serialized)
    file.close()

    if fs.exists(STATE_PATH) then
        fs.delete(STATE_PATH)
    end

    fs.move(temporaryPath, STATE_PATH)
end

saveState = function()
    if not shaftWidth then
        return
    end

    writeStateFile({
        version = 1,
        status = stateStatus,
        phase = currentPhase,
        shaftWidth = shaftWidth,
        requestedDepth = requestedDepth,
        batchSize = batchSize,
        completedDepth = completedDepth,
        stairActions = copyList(stairActions),
        stairStepsDone = stairStepsDone,
        stairSideIndex = stairSideIndex,
        stairSideMovesDone = stairSideMovesDone,
        stairPathProgress = stairPathProgress,
        stairsInitialized = stairsInitialized,
        x = x,
        y = y,
        z = z,
        facing = facing,
    })
end

local function setPhase(phase)
    currentPhase = phase
    saveState()
end

local function markRunning(phase)
    stateStatus = "running"
    currentPhase = phase or currentPhase
    saveState()
end

local function markStopped(phase)
    stateStatus = "stopped"
    currentPhase = phase or currentPhase
    saveState()
end

local function loadStateFile()
    if not fs.exists(STATE_PATH) then
        return nil
    end

    local file = fs.open(STATE_PATH, "r")

    if not file then
        return nil
    end

    local contents = file.readAll()
    file.close()

    local state = textutils.unserialize(contents)

    if type(state) ~= "table" then
        return nil
    end

    return state
end

local function applyLoadedState(state)
    shaftWidth = state.shaftWidth
    requestedDepth = state.requestedDepth
    batchSize = state.batchSize or batchSize
    completedDepth = state.completedDepth or 0
    stairActions = copyList(state.stairActions)
    stairStepsDone = state.stairStepsDone or 0
    stairSideIndex = state.stairSideIndex or 1
    stairSideMovesDone = state.stairSideMovesDone or 0
    stairPathProgress = state.stairPathProgress or 0
    stairsInitialized = state.stairsInitialized or false
    x = state.x or 0
    y = state.y or 0
    z = state.z or 0
    facing = state.facing or DIR_EAST
    stateStatus = state.status or "running"
    currentPhase = state.phase or "resume"
    stateLoaded = true
end

local function activeStateExists()
    local state = loadStateFile()
    return state and state.status ~= "stopped"
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
    saveState()
end

local function turnRight()
    turtle.turnRight()
    facing = (facing + 1) % 4
    saveState()
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
            saveState()
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
            saveState()
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
            saveState()
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

local function clearTunnelHeight(height)
    height = height or STAIR_TUNNEL_HEIGHT

    if height < 2 then
        return true
    end

    local climbed = 0

    for level = 1, height - 1 do
        local cleared, reason = clearUp()

        if not cleared then
            for _ = 1, climbed do
                mustMove(moveDown())
            end

            return false, reason
        end

        if level < height - 1 then
            local moved, moveReason = moveUp()

            if not moved then
                for _ = 1, climbed do
                    mustMove(moveDown())
                end

                return false, moveReason
            end

            climbed = climbed + 1
        end
    end

    for _ = 1, climbed do
        mustMove(moveDown())
    end

    return true
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
    stairPathProgress = 0
    saveState()
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

if resumeMode then
    local state = loadStateFile()

    if not state or state.status == "stopped" then
        print("No active miner state to resume.")
        return
    end

    if not state.shaftWidth then
        print("Miner state is missing shaftWidth; cannot resume.")
        return
    end

    applyLoadedState(state)
    stateStatus = "running"
    saveState()
    print("Loaded miner state from " .. STATE_PATH)
else
    local argumentOffset = recoverMode and 1 or 0
    local widthArg = args[1 + argumentOffset]
    local depthArg = args[2 + argumentOffset]
    local batchArg = args[3 + argumentOffset]

    if activeStateExists() then
        print("An active miner state already exists.")

        if not readYesNo("Replace it and start a new run", false) then
            print("Cancelled.")
            return
        end
    end

    shaftWidth = tonumber(widthArg)
    requestedDepth = tonumber(depthArg)

    if not shaftWidth then
        shaftWidth = readNumber("Shaft diameter/width in blocks (even)", 8, false)
    end

    while shaftWidth < 2 or shaftWidth % 2 ~= 0 do
        print("Use an even shaft diameter, such as 6, 8, 10, or 12.")
        shaftWidth = readNumber("Shaft diameter/width in blocks (even)", 8, false)
    end

    if depthArg == "bedrock" then
        requestedDepth = nil
    elseif not requestedDepth then
        requestedDepth = readNumber("Depth to dig, blank for bedrock", nil, true)
    end

    while requestedDepth ~= nil and requestedDepth < 1 do
        print("Depth must be at least 1.")
        requestedDepth = readNumber("Depth to dig, blank for bedrock", nil, true)
    end

    batchSize = tonumber(batchArg) or batchSize

    while batchSize < 1 do
        print("Batch size must be at least 1.")
        batchSize = readNumber("Shaft levels before unload/stair catch-up", 5, false)
    end
end

outerWidth = shaftWidth + 4
sideLength = outerWidth - 1

print("")
print("Square shaft staircase")
print("Shaft diameter: " .. shaftWidth)
print("Outer width: " .. outerWidth)
print("Shaft workspace headroom: " .. WORKSPACE_HEADROOM .. " above floor")
print("Stair tunnel height: " .. STAIR_TUNNEL_HEIGHT)
print("Batch size: " .. batchSize .. " shaft levels")

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

if not resumeMode then
    if recoverMode then
        print("Recover mode: state will be rebuilt by scanning the existing center shaft.")
    end

    if not readYesNo("Ready to start", true) then
        print("Cancelled.")
        return
    end
else
    print("Resume mode: continuing saved miner state.")
end

waitForFuel(20, "Add starting fuel to the turtle.")
markRunning(currentPhase)

local advanceStairsTo
local moveFromCurrentStairToShaft
local moveToShaftStartAtDepth
local serviceByStairs

local function maybeServiceShaft()
    if inventoryNeedsUnload() then
        serviceByCoordinates("Inventory nearly full.", true)
    elseif fuelLevel() < distanceToHome() + 30 then
        serviceByCoordinates("Fuel is low.", true)
    end
end

local function isTorchBlock(name)
    return type(name) == "string" and name:find("torch", 1, true) ~= nil
end

local function scanExistingShaftDepth()
    print("")
    print("Recovery scan: measuring existing center shaft depth...")
    setPhase("recover_scan")

    moveToDepth(0)
    moveToX(shaftOffset)
    moveToZ(shaftOffset)
    turnTo(DIR_EAST)

    local scannedDepth = 0

    while requestedDepth == nil or scannedDepth < requestedDepth do
        if turtle.detectDown() then
            local ok, data = turtle.inspectDown()

            if ok and data and isTorchBlock(data.name) then
                local cleared, reason = clearDown()

                if not cleared then
                    return false, reason
                end
            else
                break
            end
        end

        local moved, reason = moveDown()

        if not moved then
            return false, reason
        end

        scannedDepth = scannedDepth + 1

        if scannedDepth % batchSize == 0 then
            print("Recovery scan depth: " .. scannedDepth)
        end
    end

    completedDepth = scannedDepth
    stairActions = {}
    stairStepsDone = 0
    stairSideIndex = 1
    stairSideMovesDone = 0
    stairPathProgress = 0
    stairsInitialized = false

    print("Recovery scan found completed shaft depth: " .. completedDepth)
    setPhase("shaft")
    saveState()
    return true
end

local function mineShaftLayer()
    for row = 1, shaftWidth do
        for column = 1, shaftWidth do
            maybeServiceShaft()

            local cleared, reason = clearTunnelHeight(WORKSPACE_TUNNEL_HEIGHT)

            if not cleared then
                return false, reason
            end

            cleared, reason = clearDown()

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

    local stopReason = nil
    local batchProgress = 0

    while requestedDepth == nil or completedDepth < requestedDepth do
        print("Mining shaft layer " .. tostring(completedDepth + 1) .. "...")
        setPhase("shaft")
        moveToShaftStartAtDepth(completedDepth)

        local ok, reason = mineShaftLayer()

        if not ok then
            stopReason = reason
            break
        end

        completedDepth = completedDepth + 1
        batchProgress = batchProgress + 1
        saveState()
        print("Central shaft depth: " .. completedDepth)

        local reachedTarget = requestedDepth ~= nil and completedDepth >= requestedDepth
        local shouldCatchUp = reachedTarget or batchProgress >= batchSize

        if shouldCatchUp then
            batchProgress = 0
            serviceByCoordinates("Unloading shaft batch through depth " .. completedDepth .. ".", false)
            setPhase("home")

            local stairsOk, stairsReason = advanceStairsTo(completedDepth, reachedTarget)

            if not stairsOk then
                stopReason = "staircase stopped: " .. tostring(stairsReason)
                break
            end

            if reachedTarget then
                break
            end

            if not moveFromCurrentStairToShaft() then
                print("Could not enter shaft directly from stair end; using staircase return.")
                serviceByStairs("Returning to chest before continuing shaft.", false)
            end

            moveToShaftStartAtDepth(completedDepth)
            setPhase("shaft")
        else
            local moved, moveReason = moveDown()

            if not moved then
                stopReason = moveReason
                break
            end
        end
    end

    if x ~= 0 or y ~= 0 or z ~= 0 then
        serviceByCoordinates("Central shaft phase finished.", false)
        setPhase("home")
    end

    if stairStepsDone < completedDepth then
        print("Catching staircase up to completed shaft depth...")
        local stairsOk, stairsReason = advanceStairsTo(completedDepth, true)

        if not stairsOk then
            stopReason = stopReason or ("staircase stopped: " .. tostring(stairsReason))
        end
    end

    return completedDepth, stopReason
end

local function stairReturnCost()
    local cost = 0

    for _, action in ipairs(stairActions) do
        if action == "step" then
            cost = cost + 2
        elseif action == "landing" then
            cost = cost + 1
        end
    end

    return cost
end

local function atHome()
    return x == 0 and y == 0 and z == 0
end

local function isInShaftCell(cellX, cellZ)
    return cellX >= shaftOffset and cellX < shaftOffset + shaftWidth and
        cellZ >= shaftOffset and cellZ < shaftOffset + shaftWidth
end

local function directionFromDelta(deltaX, deltaZ)
    if deltaX == 1 and deltaZ == 0 then
        return DIR_EAST
    elseif deltaX == -1 and deltaZ == 0 then
        return DIR_WEST
    elseif deltaX == 0 and deltaZ == 1 then
        return DIR_SOUTH
    elseif deltaX == 0 and deltaZ == -1 then
        return DIR_NORTH
    end

    return nil
end

local function stairStateAtProgress(progress)
    local state = {
        x = 0,
        y = 0,
        z = 0,
        facing = DIR_EAST,
    }

    for index = 1, math.min(progress, #stairActions) do
        local action = stairActions[index]

        if action == "right" then
            state.facing = (state.facing + 1) % 4
        elseif action == "landing" then
            state.x = state.x + dx[state.facing]
            state.z = state.z + dz[state.facing]
        elseif action == "step" then
            state.x = state.x + dx[state.facing]
            state.z = state.z + dz[state.facing]
            state.y = state.y + 1
        end
    end

    return state
end

local function shaftEntryForStairState(state)
    local right = (state.facing + 1) % 4
    local innerX = state.x + dx[right]
    local innerZ = state.z + dz[right]
    local candidates = {
        { x = innerX + 1, z = innerZ },
        { x = innerX - 1, z = innerZ },
        { x = innerX, z = innerZ + 1 },
        { x = innerX, z = innerZ - 1 },
    }

    for _, candidate in ipairs(candidates) do
        if isInShaftCell(candidate.x, candidate.z) then
            return {
                shaftX = candidate.x,
                shaftZ = candidate.z,
                innerX = innerX,
                innerZ = innerZ,
                fromShaftToInner = directionFromDelta(innerX - candidate.x, innerZ - candidate.z),
                fromInnerToPath = (state.facing + 3) % 4,
            }
        end
    end

    return nil
end

local function moveToStairProgressThroughShaft(progress)
    local state = stairStateAtProgress(progress)
    local entry = shaftEntryForStairState(state)

    if not entry or not entry.fromShaftToInner then
        return false
    end

    goToPosition({
        x = entry.shaftX,
        y = state.y,
        z = entry.shaftZ,
        facing = entry.fromShaftToInner,
    })

    mustMove(moveForward())
    turnTo(entry.fromInnerToPath)
    mustMove(moveForward())
    turnTo(state.facing)

    stairPathProgress = progress
    saveState()
    return true
end

local function fastEnterStairPath()
    if not atHome() or stairPathProgress ~= 0 or #stairActions == 0 then
        return false
    end

    for progress = #stairActions, 1, -1 do
        if shaftEntryForStairState(stairStateAtProgress(progress)) then
            print("Fast-entering staircase at saved action " .. progress .. "/" .. #stairActions)
            return moveToStairProgressThroughShaft(progress)
        end
    end

    return false
end

moveFromCurrentStairToShaft = function()
    local state = stairStateAtProgress(stairPathProgress)
    local entry = shaftEntryForStairState(state)

    if not entry or not entry.fromShaftToInner then
        return false
    end

    turnRight()
    mustMove(moveForward())
    turnTo((entry.fromShaftToInner + 2) % 4)
    mustMove(moveForward())
    setPhase("shaft")
    return true
end

moveToShaftStartAtDepth = function(depth)
    if isInShaftCell(x, z) then
        moveToX(shaftOffset)
        moveToZ(shaftOffset)
        moveToDepth(depth)
        turnTo(DIR_EAST)
    else
        goToPosition({
            x = shaftOffset,
            y = depth,
            z = shaftOffset,
            facing = DIR_EAST,
        })
    end
end

local function returnHomeByStairs()
    waitForFuel(stairReturnCost() + 2, "Need enough fuel to climb back to the chest.")

    local startIndex = math.min(stairPathProgress, #stairActions)

    for index = startIndex, 1, -1 do
        local action = stairActions[index]

        if action == "right" then
            turnLeft()
        elseif action == "landing" then
            moveBackward()
        elseif action == "step" then
            mustMove(moveUp())
            moveBackward()
        end

        stairPathProgress = index - 1
        saveState()
    end
end

local function replayStairs()
    for index = stairPathProgress + 1, #stairActions do
        local action = stairActions[index]

        if action == "right" then
            turnRight()
        elseif action == "landing" then
            mustMove(moveForward())
        elseif action == "step" then
            mustMove(moveForward())
            mustMove(moveDown())
        end

        stairPathProgress = index
        saveState()
    end
end

serviceByStairs = function(reason, returnToWork)
    print("")
    print(reason)
    print("Returning to chest...")
    setPhase("stairs_return")
    returnHomeByStairs()
    unloadAtHome()
    setPhase("home")

    if returnToWork then
        waitForFuel(stairReturnCost() * 2 + 40, "Need more fuel before descending again.")
        print("Returning to staircase...")
        setPhase("stairs")
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

    cleared, reason = clearTunnelHeight()

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

    local cleared, reason = clearTunnelHeight()

    if not cleared then
        return false, reason
    end

    cleared, reason = clearInnerLane()

    if not cleared then
        return false, reason
    end

    stairsInitialized = true
    saveState()
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
    stairPathProgress = #stairActions
    saveState()

    cleared, reason = clearTunnelHeight()

    if not cleared then
        return false, reason
    end

    return clearInnerLane()
end

local function landingMove()
    local cleared, reason = clearForward()

    if not cleared then
        return false, reason
    end

    local moved, moveReason = moveForward()

    if not moved then
        return false, moveReason
    end

    stairActions[#stairActions + 1] = "landing"
    stairPathProgress = #stairActions
    saveState()

    cleared, reason = clearTunnelHeight()

    if not cleared then
        return false, reason
    end

    return clearInnerLane()
end

local function makeCornerLandingIfNeeded()
    if stairSideMovesDone == 0 or stairSideMovesDone % sideLength ~= 0 then
        return true
    end

    turnRight()
    stairActions[#stairActions + 1] = "right"
    stairPathProgress = #stairActions
    stairSideIndex = (stairSideIndex % 4) + 1
    stairSideMovesDone = 0
    saveState()

    for _ = 1, 2 do
        local ok, reason = landingMove()

        if not ok then
            return false, reason
        end

        stairSideMovesDone = stairSideMovesDone + 1
        saveState()
    end

    print("Corner landing made on side " .. stairSideIndex)
    return true
end

advanceStairsTo = function(targetDepth, returnHomeWhenDone)
    if targetDepth <= stairStepsDone then
        return true
    end

    if returnHomeWhenDone == nil then
        returnHomeWhenDone = true
    end

    print("")
    print("Extending staircase to depth " .. targetDepth .. "...")
    setPhase("stairs")
    turnTo(DIR_EAST)

    local ready, reason = ensureStairsInitialized()

    if not ready then
        return false, reason
    end

    if stairPathProgress == 0 and #stairActions > 0 then
        fastEnterStairPath()
    end

    replayStairs()

    while stairStepsDone < targetDepth do
        maybeServiceStairs()

        local landingOk, landingReason = makeCornerLandingIfNeeded()

        if not landingOk then
            serviceByStairs("Staircase stopped while making a corner landing.", false)
            return false, landingReason
        end

        local nextStep = stairStepsDone + 1
        local ok, stepReason = stairStep()

        if not ok then
            serviceByStairs("Staircase stopped before catching up.", false)
            return false, stepReason
        end

        stairStepsDone = nextStep
        stairSideMovesDone = stairSideMovesDone + 1
        saveState()
        print("Stair depth: " .. stairStepsDone .. "/" .. targetDepth ..
            " (side " .. stairSideIndex .. ", offset " .. stairSideMovesDone .. ")")
    end

    if returnHomeWhenDone then
        serviceByStairs("Staircase caught up to shaft depth.", false)
    else
        setPhase("stairs")
    end

    return true
end

local function phaseLooksLikeStairs()
    return currentPhase and currentPhase:find("stairs", 1, true) ~= nil
end

local function recoverLoadedState()
    if not resumeMode or not stateLoaded then
        return true
    end

    print("")
    print("Recovering saved miner state...")
    print("Saved phase: " .. tostring(currentPhase))
    print("Saved position: " .. x .. "," .. y .. "," .. z)

    if not atHome() then
        if phaseLooksLikeStairs() then
            print("Returning from staircase path to chest...")
            returnHomeByStairs()
            unloadAtHome()
            setPhase("home")
        else
            serviceByCoordinates("Returning from saved shaft position.", false)
            setPhase("home")
        end
    end

    if stairStepsDone < completedDepth then
        print("Catching staircase up to completed shaft depth...")
        local ok, reason = advanceStairsTo(completedDepth)

        if not ok then
            return false, reason
        end
    end

    return true
end

if recoverMode then
    local scanned, scanReason = scanExistingShaftDepth()

    if not scanned then
        print("")
        print("Recovery scan failed: " .. tostring(scanReason))
        markStopped("recover_failed")
        return
    end
end

local recovered, recoveryReason = recoverLoadedState()

if not recovered then
    print("")
    print("Resume recovery failed: " .. tostring(recoveryReason))
    return
end

local completedShaftDepth, shaftStopReason = mineCentralShaft()

if completedShaftDepth <= 0 then
    print("")
    print("Stopped before any usable shaft depth was completed.")

    if shaftStopReason then
        print("Reason: " .. shaftStopReason)
    end

    markStopped("stopped")
    return
end

print("")
print("Done.")
print("Central shaft depth: " .. completedShaftDepth)
print("Staircase depth: " .. stairStepsDone)

if shaftStopReason then
    print("Shaft stopped at bedrock/blocked block: " .. shaftStopReason)
end

markStopped("complete")
