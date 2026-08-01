local owner = "johansolbakken"
local repository = "mylua"
local branch = "main"

local files = {
    "loader.lua",
    "lib/ae2_storage.lua",
    "lib/items.lua",
    "lib/log.lua",
    "lib/log_render.lua",
    "lib/peripherals.lua",
    "bin/ae2_storage.lua",
    "bin/log_monitor.lua",
    "bin/horizontal_miner.lua",
    "bin/my_turtle.lua",
    "bin/my_turtle_startup.lua",
    "bin/room.lua",
    "bin/room_sign.lua",
    "bin/sorter_turtle.lua",
    "bin/stair_builder.lua",
    "bin/storage.lua",
    "bin/storage_room.lua",
    "bin/turtle_log_monitor.lua",
}

local legacyFiles = {
    "my_turtle.lua",
    "my_turtle_startup.lua",
    "room_sign.lua",
    "sorter_turtle.lua",
    "stair_builder.lua",
    "storage_room.lua",
    "turtle_log_monitor.lua",
}

local function getLatestCommit()
    local url = string.format(
        "https://api.github.com/repos/%s/%s/branches/%s?t=%d",
        owner,
        repository,
        branch,
        os.epoch("utc")
    )

    local response, err = http.get({
        url = url,
        headers = {
            ["Accept"] = "application/vnd.github+json",
            ["Cache-Control"] = "no-cache",
        },
    })

    if not response then
        error("Could not find latest commit: " .. tostring(err), 0)
    end

    local body = response.readAll()
    response.close()

    local data = textutils.unserializeJSON(body)

    if not data or not data.commit or not data.commit.sha then
        error("Invalid response from GitHub API", 0)
    end

    return data.commit.sha
end

local function downloadFile(commit, path)
    local url = string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        owner,
        repository,
        commit,
        path
    )

    print("Downloading " .. path)

    local response, err = http.get({
        url = url,
        headers = {
            ["Cache-Control"] = "no-cache",
        },
    })

    if not response then
        printError(path .. ": " .. tostring(err))
        return false
    end

    local contents = response.readAll()
    response.close()

    local directory = fs.getDir(path)

    if directory ~= "" then
        fs.makeDir(directory)
    end

    local temporaryPath = path .. ".download"
    local output = fs.open(temporaryPath, "w")

    if not output then
        printError("Cannot write " .. temporaryPath)
        return false
    end

    output.write(contents)
    output.close()

    if fs.exists(path) then
        fs.delete(path)
    end

    fs.move(temporaryPath, path)

    print("Updated " .. path)
    return true
end

local commit = getLatestCommit()

print("Commit: " .. commit:sub(1, 7))

local updated = 0

for _, path in ipairs(files) do
    if downloadFile(commit, path) then
        updated = updated + 1
    end
end

for _, path in ipairs(legacyFiles) do
    if fs.exists(path) and not fs.isDir(path) then
        fs.delete(path)
        print("Removed old " .. path)
    end
end

print(string.format("Updated %d/%d files", updated, #files))
