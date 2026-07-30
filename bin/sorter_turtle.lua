local log = require("/lib.log")
local items = require("/lib.items")

local INPUT = "front"
local STORAGE = "back"
local TRASH = "down"
local nativePrint = print
local logger = log.start({
    source = "sorter_turtle",
    nativePrint = nativePrint,
    context = function()
        return {
            status = "sorting",
        }
    end,
})

local function print(...)
    nativePrint(...)
end

local function turnAround()
    turtle.turnRight()
    turtle.turnRight()
end

local function dropToStorage()
    turnAround()

    while turtle.getItemCount() > 0 do
        if not turtle.drop() then
            logger:warn("Storage full; waiting...", {
                event = "output_blocked",
                output = "storage",
            })
            sleep(5)
        end
    end

    turnAround()
end

local function dropToTrash()
    while turtle.getItemCount() > 0 do
        if not turtle.dropDown() then
            logger:warn("Trash output blocked; waiting...", {
                event = "output_blocked",
                output = "trash",
            })
            sleep(5)
        end
    end
end

logger:info("ATM10 quarry sorter running", {
    event = "sorter_start",
    input = INPUT,
    storage = STORAGE,
    trash = TRASH,
})

while true do
    turtle.select(1)

    if turtle.getItemCount(1) == 0 then
        if not turtle.suck() then
            sleep(1)
        end
    end

    local item = turtle.getItemDetail(1, true)

    if item then
        if items.isValuable(item) then
            logger:info("KEEP: " .. item.name, {
                event = "sort_item",
                decision = "keep",
                output = "storage",
                item = item.name,
                count = item.count,
            })
            dropToStorage()
        elseif items.isJunk(item) then
            logger:info("TRASH: " .. item.name, {
                event = "sort_item",
                decision = "trash",
                output = "trash",
                item = item.name,
                count = item.count,
            })
            dropToTrash()
        else
            logger:warn("UNKNOWN, KEEPING: " .. item.name, {
                event = "sort_item",
                decision = "unknown_keep",
                output = "storage",
                item = item.name,
                count = item.count,
            })
            dropToStorage()
        end
    end
end
