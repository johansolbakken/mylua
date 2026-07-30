local args = { ... }
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

local exactBuildBlocks = {
    ["minecraft:stone"] = true,
    ["minecraft:smooth_stone"] = true,
    ["minecraft:cobblestone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:blackstone"] = true,
    ["minecraft:basalt"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:netherrack"] = true,
}

local buildWords = {
    "cobblestone",
    "cobbled",
    "deepslate",
    "blackstone",
    "basalt",
    "limestone",
    "marble",
    "tuff",
}

local x = 0
local y = 0
local z = 0
local facing = DIR_EAST
local actions = {}
local stairDepth = 0
local sideIndex = 1
local sideMovesDone = 0
local shaftWidth = nil
local depth = nil
local logger = log.start({
    source = "stair_builder",
    nativePrint = nativePrint,
    context = function()
        return {
            x = x,
            y = y,
            z = z,
            facing = facing,
            stairDepth = stairDepth,
            targetDepth = depth,
            side = sideIndex,
            offset = sideMovesDone,
        }
    end,
})

local function print(...)
    nativePrint(...)
end

local function readNumber(prompt, default)
    while true do
        if default then
            write(prompt .. " [" .. default .. "]: ")
        else
            write(prompt .. ": ")
        end

        local input = read()

        if input == "" and default then
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
        logger:warn(context, {
            event = "fuel_wait",
            fuel = fuelLevel(),
            required = required,
        })
        print("Fuel: " .. tostring(fuelLevel()) .. ", need at least " .. tostring(required) .. ".")
        print("Add fuel to the turtle, then press Enter.")
        read()
        tryRefuelFromInventory()
    end
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
            return false, "path blocked forward"
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
            waitForFuel(1, "The turtle is out of fuel.")
        elseif turtle.detectDown() then
            return false, "path blocked below"
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
            waitForFuel(1, "The turtle is out of fuel.")
        elseif turtle.detectUp() then
            return false, "path blocked above"
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

local function actionTravelCost()
    local cost = 0

    for _, action in ipairs(actions) do
        if action == "step" then
            cost = cost + 2
        elseif action == "landing" then
            cost = cost + 1
        end
    end

    return cost
end

local function returnToStart()
    waitForFuel(actionTravelCost() + 2, "Need fuel to return to the start.")

    for index = #actions, 1, -1 do
        local action = actions[index]

        if action == "right" then
            turnLeft()
        elseif action == "landing" then
            moveBackward()
        elseif action == "step" then
            mustMove(moveUp())
            moveBackward()
        end
    end
end

local function replayPath()
    waitForFuel(actionTravelCost() + 2, "Need fuel to return to the build position.")

    for _, action in ipairs(actions) do
        if action == "right" then
            turnRight()
        elseif action == "landing" then
            mustMove(moveForward())
        elseif action == "step" then
            mustMove(moveForward())
            mustMove(moveDown())
        end
    end
end

local function itemLooksBuildable(detail)
    if not detail or not detail.name then
        return false
    end

    if exactBuildBlocks[detail.name] then
        return true
    end

    local path = detail.name:match(":(.+)$") or detail.name

    if path == "redstone" or path:find("pickaxe", 1, true) or path:find("shovel", 1, true) then
        return false
    end

    if path:match("_stone$") or path:find("_stone_", 1, true) then
        return true
    end

    for _, word in ipairs(buildWords) do
        if path:find(word, 1, true) then
            return true
        end
    end

    return false
end

local function selectBuildSlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)

            if itemLooksBuildable(detail) then
                turtle.select(slot)
                return true
            end
        end
    end

    return false
end

local function placeDownOnce()
    if turtle.detectDown() then
        return true
    end

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)

            if itemLooksBuildable(detail) then
                turtle.select(slot)

                if turtle.placeDown() then
                    return true
                end
            end
        end
    end

    return false
end

local function refillBlocks()
    local wasAtStart = #actions == 0

    print("")
    logger:warn("Out of usable stone-like blocks.", {
        event = "block_refill",
        returnToWork = not wasAtStart,
    })

    if not wasAtStart then
        print("Returning to start for refill...")
        returnToStart()
    end

    while not selectBuildSlot() do
        print("Add stone/cobble/deepslate blocks to the turtle, then press Enter.")
        read()
    end

    if not wasAtStart then
        print("Returning to build position...")
        replayPath()
    end
end

local function ensureFloorBelow()
    while not placeDownOnce() do
        refillBlocks()
    end
end

local function buildCurrentTwoWide()
    ensureFloorBelow()

    while true do
        turnRight()
        mustMove(moveForward())

        if placeDownOnce() then
            moveBackward()
            turnLeft()
            return
        end

        moveBackward()
        turnLeft()
        refillBlocks()
    end
end

local function moveLanding()
    mustMove(moveForward())
    actions[#actions + 1] = "landing"
    buildCurrentTwoWide()
end

local function moveStepDown()
    mustMove(moveForward())
    mustMove(moveDown())
    actions[#actions + 1] = "step"
    buildCurrentTwoWide()
end

shaftWidth = tonumber(args[1])
depth = tonumber(args[2])

if not shaftWidth then
    shaftWidth = readNumber("Excavated shaft diameter/width", 6)
end

while shaftWidth < 2 or shaftWidth % 2 ~= 0 do
    print("Use an even diameter, such as 6, 8, 10, or 12.")
    shaftWidth = readNumber("Excavated shaft diameter/width", 6)
end

if not depth then
    depth = readNumber("Depth to build stairs", 32)
end

while depth < 1 do
    print("Depth must be at least 1.")
    depth = readNumber("Depth to build stairs", 32)
end

local outerWidth = shaftWidth + 4
local sideLength = outerWidth - 1

print("")
print("Two-wide stair builder")
print("Shaft diameter: " .. shaftWidth)
print("Outer tunnel width: " .. outerWidth)
print("Depth: " .. depth)
print("")
logger:info("Two-wide stair builder configured", {
    event = "stair_builder_start",
    shaftWidth = shaftWidth,
    targetDepth = depth,
    sideLength = sideLength,
})
print("Start position:")
print("- Northwest outside corner of the excavated tunnel")
print("- Facing east")
print("- Intended shaft on the turtle's right")
print("- Turtle one block above the first stair floor, or standing on it")
print("- Inventory filled with stone/cobble/deepslate")
print("")

if not readYesNo("Ready to build", true) then
    logger:warn("Cancelled.", {
        event = "cancelled",
    })
    return
end

waitForFuel((depth * 4) + 40, "Add fuel before starting.")
buildCurrentTwoWide()

while stairDepth < depth do
    if sideMovesDone > 0 and sideMovesDone % sideLength == 0 then
        turnRight()
        actions[#actions + 1] = "right"
        sideIndex = (sideIndex % 4) + 1
        sideMovesDone = 0

        for _ = 1, 2 do
            moveLanding()
            sideMovesDone = sideMovesDone + 1
        end

        logger:info("Corner platform built", {
            event = "corner_platform",
            side = sideIndex,
            offset = sideMovesDone,
        })
    end

    moveStepDown()
    stairDepth = stairDepth + 1
    sideMovesDone = sideMovesDone + 1

    logger:info("Built stair depth " .. stairDepth .. "/" .. depth, {
        event = "stair_progress",
        current = stairDepth,
        total = depth,
        stairDepth = stairDepth,
        targetDepth = depth,
        side = sideIndex,
        offset = sideMovesDone,
    })
end

print("")
logger:info("Stairs complete. Returning to start...", {
    event = "stairs_complete",
    current = stairDepth,
    total = depth,
    stairDepth = stairDepth,
    targetDepth = depth,
})
returnToStart()
logger:success("Done.", {
    event = "complete",
    current = stairDepth,
    total = depth,
})
