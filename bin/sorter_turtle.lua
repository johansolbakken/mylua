local log = require("lib.log")

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

local exactJunk = {
    ["minecraft:stone"] = true,
    ["minecraft:cobblestone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:coarse_dirt"] = true,
    ["minecraft:rooted_dirt"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:red_sand"] = true,
    ["minecraft:netherrack"] = true,
    ["minecraft:end_stone"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:calcite"] = true,
    ["minecraft:dripstone_block"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:diorite"] = true,
    ["minecraft:andesite"] = true,
}

local junkWords = {
    "cobblestone",
    "cobbled_",
    "limestone",
    "soapstone",
    "moonstone",
    "shale",
    "slate",
    "marble",
    "jasper",
    "basalt",
    "scoria",
    "scorched_stone",
    "siltstone",
    "sandstone",
    "mudstone",
    "granite",
    "diorite",
    "andesite",
    "tuff",
    "calcite",
}

local valuableExact = {
    ["minecraft:coal"] = true,
    ["minecraft:charcoal"] = true,
    ["minecraft:diamond"] = true,
    ["minecraft:emerald"] = true,
    ["minecraft:lapis_lazuli"] = true,
    ["minecraft:redstone"] = true,
    ["minecraft:quartz"] = true,
    ["minecraft:amethyst_shard"] = true,
    ["minecraft:ancient_debris"] = true,
    ["minecraft:raw_iron"] = true,
    ["minecraft:raw_copper"] = true,
    ["minecraft:raw_gold"] = true,
}

local function hasTagPrefix(item, prefix)
    if not item.tags then
        return false
    end

    for tag in pairs(item.tags) do
        if tag:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

local function isValuable(item)
    if valuableExact[item.name] then
        return true
    end

    if hasTagPrefix(item, "c:ores") then
        return true
    end

    if hasTagPrefix(item, "c:raw_materials") then
        return true
    end

    if hasTagPrefix(item, "c:gems") then
        return true
    end

    if hasTagPrefix(item, "c:dusts") then
        return true
    end

    local path = item.name:match(":(.+)$") or item.name

    -- Fallback for badly tagged modded ores.
    if path:match("_ore$") or path:match("_ore_") then
        return true
    end

    return false
end

local function isJunk(item)
    if exactJunk[item.name] then
        return true
    end

    if item.tags then
        if item.tags["c:stones"] then
            return true
        end

        if item.tags["c:cobblestones"] then
            return true
        end
    end

    local path = item.name:match(":(.+)$") or item.name

    for _, word in ipairs(junkWords) do
        if path:find(word, 1, true) then
            return true
        end
    end

    return false
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
        if isValuable(item) then
            logger:info("KEEP: " .. item.name, {
                event = "sort_item",
                decision = "keep",
                output = "storage",
                item = item.name,
                count = item.count,
            })
            dropToStorage()
        elseif isJunk(item) then
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
