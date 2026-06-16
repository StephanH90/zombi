-- Zombi Stats Exporter (server-side only).
--
-- Writes two files in the Zomboid data dir's Lua/ folder for the Zombi control
-- panel (which runs on the same host) to read. Clients never load this mod.
--
--   zombi-stats.json  - overwritten every few seconds with current state:
--       { "ts", "zombies", "players": [ {name, kills, hours, health}, ... ] }
--   zombi-events.json - appended one JSON object per line on player death.
--
-- Note: "zombies" is the loaded-chunk count, not a world-wide total.

local INTERVAL_MS = 1000
local STATS_FILE = "zombi-stats.json"
local EVENTS_FILE = "zombi-events.json"

local function jsonStr(s)
    s = tostring(s or "")
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function playersJson()
    local parts = {}
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                local health = 0
                local bd = p:getBodyDamage()
                if bd then health = bd:getOverallBodyHealth() end
                parts[#parts + 1] = string.format(
                    '{"name":%s,"kills":%d,"hours":%.1f,"health":%.1f}',
                    jsonStr(p:getUsername()),
                    p:getZombieKills() or 0,
                    p:getHoursSurvived() or 0,
                    health or 0
                )
            end
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
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
        '{"ts":%d,"players":%s,"zombies":%d}',
        getTimestampMs(), playersJson(), loadedZombieCount()
    )
    local writer = getFileWriter(STATS_FILE, true, false)
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

local function onDeath(character)
    if character and instanceof(character, "IsoPlayer") then
        local line = string.format(
            '{"kind":"death","name":%s,"ts":%d}',
            jsonStr(character:getUsername()), getTimestampMs()
        )
        local writer = getFileWriter(EVENTS_FILE, true, true)
        if writer then
            writer:writeln(line)
            writer:close()
        end
    end
end

Events.OnTickEvenPaused.Add(onTick)
Events.OnCharacterDeath.Add(onDeath)
