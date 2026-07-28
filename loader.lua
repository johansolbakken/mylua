local githubUser = "johansolbakken"
local repository = "mylua"
local branch = "main"

local files = {
    "loader.lua",
    "startup.lua",
    -- "sorter.lua",
    -- "lib/inventory.lua",
}

local baseUrl = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    githubUser,
    repository,
    branch
)

local function downloadFile(path)
    local url = baseUrl .. path
    local temporaryPath = path .. ".download"

    print("Downloading " .. path)

    local response, errorMessage = http.get(url)

    if not response then
        printError("Failed: " .. tostring(errorMessage))
        return false
    end

    local contents = response.readAll()
    response.close()

    local directory = fs.getDir(path)

    if directory ~= "" and not fs.exists(directory) then
        fs.makeDir(directory)
    end

    local file = fs.open(temporaryPath, "w")

    if not file then
        printError("Could not open " .. temporaryPath)
        return false
    end

    file.write(contents)
    file.close()

    if fs.exists(path) then
        fs.delete(path)
    end

    fs.move(temporaryPath, path)

    print("Updated " .. path)
    return true
end

local successful = 0

for _, path in ipairs(files) do
    if downloadFile(path) then
        successful = successful + 1
    end
end

print(string.format("Updated %d of %d files.", successful, #files))