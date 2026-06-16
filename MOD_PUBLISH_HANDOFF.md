# Handoff: Publish the "ZombiStats" Project Zomboid mod to the Steam Workshop

You are picking this up on a desktop machine that has **Steam and Project
Zomboid installed**. Your job: assemble a small mod and **publish it to the
Steam Workshop**, then report back the **Workshop ID**.

## Background (why this exists)

There's a Project Zomboid dedicated server (Build 42, version 42.19.0) with a
web control panel ("Zombi") running alongside it. The panel wants live
per-player stats (kills, hours survived, health) and death events. The only way
to get those is a small **server-side Lua mod** that writes them to a file the
panel reads.

A Project Zomboid dedicated server requires **every connecting client to have
every mod in the server's mod list** — even a server-side-only mod. A purely
local (unpublished) mod therefore blocks clients from joining. The fix is to
put the mod on the **Steam Workshop** so clients auto-download it silently on
next launch. That's what this task accomplishes.

The mod adds **no client-facing content** — it only runs server-side Lua — so
players won't notice anything beyond the one-time automatic download.

## Step 1 — Create the mod files

Project Zomboid Build 42 mods use a versioned folder (`42.0/`). Create this
exact tree somewhere temporary (e.g. your Desktop):

```
ZombiStats/
  42.0/
    mod.info
    media/lua/server/ZombiStats.lua
```

### `ZombiStats/42.0/mod.info`

```
name=Zombi Stats Exporter
id=ZombiStats
description=Server-side only. Writes player and loaded-zombie counts to zombi-stats.json for the Zombi control panel. Clients do not need to do anything.
author=zombi
category=Misc
versionMin=42.0.0
```

### `ZombiStats/42.0/media/lua/server/ZombiStats.lua`

```lua
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

local INTERVAL_MS = 5000
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
```

## Step 2 — Build the Workshop upload folder

Project Zomboid uploads Workshop items from a specific folder under your
Zomboid user directory:

- Windows: `%USERPROFILE%\Zomboid\Workshop\`
- Linux: `~/Zomboid/Workshop/`
- macOS: `~/Zomboid/Workshop/`

Create:

```
Zomboid/Workshop/ZombiStatsExporter/
  workshop.txt
  preview.png                     <- any small PNG (the uploader requires one)
  Contents/
    mods/
      ZombiStats/                 <- the whole folder from Step 1
        42.0/
          mod.info
          media/lua/server/ZombiStats.lua
```

### `Zomboid/Workshop/ZombiStatsExporter/workshop.txt`

```
version=1
id=
title=Zombi Stats Exporter
description=Server-side stats exporter for the Zombi control panel. Writes the online players (kills, hours survived, health) and loaded-zombie count to a file the panel reads, and logs deaths. Adds no client content.
tags=Misc
visibility=public
```

Leave `id=` blank — Steam fills it on first upload.

## Step 3 — Upload via the game

1. Launch Project Zomboid.
2. Main menu → **Workshop** → **Create and Upload** (it lists items found in
   `Zomboid/Workshop/`).
3. Select **ZombiStatsExporter**, confirm the title/description, set visibility
   to **Public**, accept the Steam Workshop Legal Agreement, and **Upload**.
4. Steam opens the published item's page in a browser/overlay. The URL ends
   with `?id=XXXXXXXXXX` — **that number is the Workshop ID.**

## Step 4 — Report back

Provide the **Workshop ID** (the number). The server side will then:

- add it to `WorkshopItems=` in the server's `.ini`,
- add `ZombiStats` to the `Mods=` line,
- restart the server.

After that, clients auto-download the mod on next launch and the control
panel's Players tab fills in with live stats. Nothing else is required from
players.

## Troubleshooting

- **Upload button greyed out / item not listed:** the folder must be exactly
  `Zomboid/Workshop/<Name>/Contents/mods/<ModName>/...` and contain a
  `workshop.txt` and a `preview.png` at the `<Name>/` level.
- **Mod not recognized in-game:** check `mod.info` has `id=ZombiStats` and lives
  under the `42.0/` version folder.
- This mod has no visible in-game effect by design — it only writes files on the
  server. Don't expect a UI change; success is just a published Workshop item.
