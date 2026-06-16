-- Zombi Stats Exporter (server-side only).
--
-- Every few seconds, writes a small JSON file with the current player count
-- and the number of loaded zombies. The Zombi control panel reads this file
-- (it runs on the same host) and shows the numbers. Clients never load this.
--
-- Note: zombies only exist as real objects in chunks loaded around players, so
-- this is the loaded-zombie count, not a world-wide total.

local INTERVAL_MS = 5000
local OUTPUT_FILE = "zombi-stats.json"

local function playerCount()
    local players = getOnlinePlayers()
    if players then return players:size() end
    return 0
end

local function loadedZombieCount()
    local cell = getCell()
    if cell then
        local zombies = cell:getZombieList()
        if zombies then return zombies:size() end
    end
    return 0
end

local function writeStats()
    local json = string.format(
        '{"ts":%d,"players":%d,"zombies":%d}',
        getTimestampMs(),
        playerCount(),
        loadedZombieCount()
    )

    -- getFileWriter writes relative to the Zomboid data directory.
    local writer = getFileWriter(OUTPUT_FILE, true, false)
    if writer then
        writer:write(json)
        writer:close()
    end
end

local lastWrite = 0
local function onTick()
    local now = getTimestampMs()
    if now - lastWrite >= INTERVAL_MS then
        lastWrite = now
        writeStats()
    end
end

Events.OnTickEvenPaused.Add(onTick)
