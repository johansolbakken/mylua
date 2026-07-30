local items = {}

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

function items.path(itemOrName)
    local name = itemOrName

    if type(itemOrName) == "table" then
        name = itemOrName.name
    end

    if type(name) ~= "string" then
        return ""
    end

    return name:match(":(.+)$") or name
end

function items.hasTagPrefix(item, prefix)
    if type(item) ~= "table" or not item.tags then
        return false
    end

    for tag in pairs(item.tags) do
        if tag:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

function items.isValuable(item)
    if type(item) ~= "table" or type(item.name) ~= "string" then
        return false
    end

    if valuableExact[item.name] then
        return true
    end

    if items.hasTagPrefix(item, "c:ores") then
        return true
    end

    if items.hasTagPrefix(item, "c:raw_materials") then
        return true
    end

    if items.hasTagPrefix(item, "c:gems") then
        return true
    end

    if items.hasTagPrefix(item, "c:dusts") then
        return true
    end

    local path = items.path(item)

    -- Fallback for badly tagged modded ores.
    if path:match("_ore$") or path:match("_ore_") then
        return true
    end

    return false
end

function items.isJunk(item)
    if type(item) ~= "table" or type(item.name) ~= "string" then
        return false
    end

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

    local path = items.path(item)

    for _, word in ipairs(junkWords) do
        if path:find(word, 1, true) then
            return true
        end
    end

    return false
end

function items.isTorch(item)
    local path = items.path(item)

    return path:find("torch", 1, true) ~= nil and path ~= "redstone_torch"
end

function items.isSupply(item)
    return items.isTorch(item)
end

function items.isGoods(item)
    if type(item) ~= "table" or type(item.name) ~= "string" then
        return false
    end

    return not items.isJunk(item) and not items.isSupply(item)
end

return items
