# mylua

ComputerCraft Lua programs developed locally and synced into Minecraft computers.

## Layout

- `loader.lua` stays at the repo root. It is the bootstrap/update script to run on a ComputerCraft computer.
- `bin/` contains runnable programs.
- `lib/` contains reusable modules for programs in `bin/`.
- `lib/items.lua` contains shared item classification for junk, goods, valuables, and torches.

Current programs:

- `bin/my_turtle.lua`: square shaft miner with staircase support
- `bin/my_turtle_startup.lua`: resumes an active `my_turtle` state
- `bin/horizontal_miner.lua`: straight horizontal goods miner with junk discard, torch placement, and chest unloads
- `bin/room.lua`: rectangular room miner with junk discard, torch placement, and chest unloads
- `bin/log_monitor.lua`: generic monitor display for distributed logs
- `bin/turtle_log_monitor.lua`: compatibility alias for `bin/log_monitor.lua`
- `bin/room_sign.lua`: configurable room sign monitor
- `bin/storage_room.lua`: fixed storage room sign
- `bin/sorter_turtle.lua`: quarry item sorter
- `bin/stair_builder.lua`: standalone stair builder

## Loader

`loader.lua` downloads the latest files from the `main` branch of this GitHub repo using the GitHub API and raw file URLs.

Initialize a new in-game computer by downloading only the loader first:

```text
wget https://raw.githubusercontent.com/johansolbakken/mylua/main/loader.lua loader.lua
```

Then run the loader to download the rest of the repo files:

```text
loader
```

If `wget` is unavailable, enable HTTP in the ComputerCraft config for the world/server and try again.

After the first install, update the computer by running:

```text
loader
```

The loader:

- finds the latest commit on `main`
- downloads `loader.lua`, every listed `bin/*.lua` program, and every listed `lib/*.lua` module
- creates directories before writing files
- writes through temporary `.download` files before replacing existing files
- removes old top-level program files that were moved into `bin/`

When adding files, update the `files` table in `loader.lua`. If a file was renamed or moved and old in-game copies should be deleted, add the old path to `legacyFiles`.

## Adding A New Program

1. Create the program under `bin/`, for example `bin/farm_turtle.lua`.
2. Add it to the `files` table in `loader.lua`:

```lua
local files = {
    "loader.lua",
    "lib/items.lua",
    "lib/log.lua",
    "lib/log_render.lua",
    "lib/peripherals.lua",
    "bin/farm_turtle.lua",
}
```

3. Run a syntax check locally:

```sh
luac -p loader.lua lib/*.lua bin/*.lua
```

4. Commit and push to `main`.
5. Run `loader` on each ComputerCraft computer that should receive the update.

Run bin programs by path:

```lua
shell.run("bin/farm_turtle")
```

From the shell prompt, use:

```text
bin/farm_turtle
```

## Horizontal Miner

`bin/horizontal_miner.lua` digs a straight 1-wide, 2-high tunnel. It drops stone-like junk below the turtle, keeps ores and unknown non-junk items, places torches in side pockets, and returns to the chest behind the start position when inventory is nearly full.

Start position:

- turtle faces the direction to mine
- chest or inventory is directly behind the turtle
- torches are in the turtle inventory
- fuel is already loaded or available in the turtle inventory

Run with a fixed tunnel length and default torch spacing of 8:

```text
bin/horizontal_miner 128
```

Run with a custom torch spacing:

```text
bin/horizontal_miner 128 6
```

Run until stopped manually:

```text
bin/horizontal_miner forever 8
```

The miner uses `/lib.items` for junk/goods classification and `/lib.log` for structured events such as `tunnel_progress`, `torch_place`, `goods_unload`, and `mine_complete`. Progress and unload logs include a `junkDropped` counter.

## Room Miner

`bin/room.lua` digs a rectangular room from arguments in `x z y` order:

```text
bin/room 9 12 4
```

That command clears a room 9 blocks wide, 12 blocks deep, and 4 blocks high. The turtle mines layer by layer from bottom to top, drops stone-like junk below itself, keeps goods, places torches in small wall pockets, and returns to the chest behind the start position when inventory is nearly full.

Start position:

- turtle is at the front-left-bottom entrance, just outside the room
- turtle faces into the room depth direction
- chest or inventory is directly behind the turtle
- torches are in the turtle inventory if torch placement is enabled
- fuel is already loaded or available in the turtle inventory

Use a custom torch spacing:

```text
bin/room 9 12 4 6
```

Disable torches:

```text
bin/room 9 12 4 0
```

The room miner uses `/lib.items` for junk/goods classification and `/lib.log` for structured events such as `room_progress`, `torch_place`, `goods_unload`, and `room_complete`.

## Peripheral Discovery

Use `lib.peripherals` when a program needs a modem, monitor, or other peripheral.

```lua
local peripherals = require("/lib.peripherals")
```

Find any monitor:

```lua
local monitorName, monitor = peripherals.findMonitor()

if not monitor then
    error("No monitor found", 0)
end
```

Prefer a named side or peripheral:

```lua
local monitorName, monitor = peripherals.findMonitor("back")
```

Require a specific side:

```lua
local _, monitor = peripherals.findMonitor({
    preferredName = "back",
    strictPreferred = true,
})
```

Wait until a monitor is attached:

```lua
local monitorName, monitor = peripherals.waitForMonitor({
    monitorName = "top",
    waitingMessage = "Attach the status monitor.",
})
```

Open rednet on the best modem:

```lua
local modemName, reason = peripherals.openRednet()

if not modemName then
    error("Could not open rednet: " .. tostring(reason), 0)
end
```

Useful options:

- `preferredName`, `name`, `modemName`, or `monitorName`: preferred peripheral side/name
- `strictPreferred`: only accept the preferred peripheral
- `preferWireless`: for modems, defaults to `true`
- `filter`: function called as `filter(name, wrappedPeripheral)`
- `waitingMessage`: message printed by `waitForMonitor`
- `onMissing`: callback used by `waitForMonitor` instead of `waitingMessage`

## Distributed Logging

Use `lib.log` for programs that should broadcast logs over rednet.

```lua
local log = require("/lib.log")
```

Start logging:

```lua
local logger = log.start({
    source = "farm_turtle",
})

logger:print("started")
```

`logger:print(...)` prints locally and broadcasts the same message if a modem is available. If no modem/rednet is available, local printing still works and `logger.enabled` is `false`.

For structured logs, prefer the level helpers:

```lua
logger:info("harvested wheat", {
    event = "harvest",
    item = "minecraft:wheat",
    count = 12,
})

logger:warn("inventory full", {
    event = "inventory_full",
    slot = 16,
})

logger:error("blocked by bedrock", {
    event = "dig_blocked",
    reason = "Unbreakable block detected",
})
```

Add dynamic context fields to every log:

```lua
local x, y, z = 0, 0, 0

local logger = log.start({
    source = "miner",
    context = function()
        return {
            x = x,
            y = y,
            z = z,
            phase = "dig",
        }
    end,
})

logger:print("cleared layer")
```

Send one log without local printing:

```lua
logger:send("inventory full", {
    level = "warn",
    event = "inventory_full",
    slot = 16,
})
```

Replace a program's local `print` with distributed logging:

```lua
local nativePrint = print
local logger = log.start({
    source = "my_program",
    nativePrint = nativePrint,
})

local function print(...)
    logger:print(...)
end
```

### Log Monitor

Set up a separate ComputerCraft computer with a modem and monitor, then run:

```text
bin/log_monitor
```

To require a specific monitor side/name:

```text
bin/log_monitor back
```

`bin/turtle_log_monitor` still exists as an alias for old setups.

The monitor listens for log payloads and writes them to the attached monitor. It uses `lib/log_render.lua` to split each payload into a headline and a compact details row. Known fields such as position, level, phase, status, fuel, progress, item, count, decision, output, and reason get stable labels; unknown custom fields are appended after those.

For startup, create `startup.lua` in the computer root:

```lua
local requiredFiles = {
    "loader.lua",
    "lib/log.lua",
    "lib/log_render.lua",
    "lib/peripherals.lua",
    "bin/log_monitor.lua",
}

for _, path in ipairs(requiredFiles) do
    if not fs.exists(path) then
        shell.run("loader")
        break
    end
end

shell.run("bin/log_monitor")
```

For a specific monitor side/name:

```lua
shell.run("bin/log_monitor", "back")
```

The current protocol constants are:

- protocol: `mylua:log`
- payload magic: `MYLUA_LOG_V1`
- payload version: `1`

The standard payload fields are:

- `magic`, `kind`, `version`
- `source`, `computerId`, `label`
- `message`, `level`, `event`, `time`
- `context`: common dynamic fields added by the logger
- `data`: per-message fields

Programs may add fields such as `x`, `y`, `z`, `facing`, `phase`, `status`, `fuel`, `required`, `current`, `total`, `item`, `count`, `decision`, `output`, and `reason`.
