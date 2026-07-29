local STATE_PATH = "my_turtle.state"
local PROGRAM = "my_turtle"

local function loadState()
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

local state = loadState()

if state and state.status ~= "stopped" then
    print("Resuming " .. PROGRAM .. " from " .. STATE_PATH)
    shell.run(PROGRAM, "resume")
else
    print("No active miner state.")
end
