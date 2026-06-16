# Publishing ZombiStats to the Steam Workshop

The dedicated server requires every client to have each mod in its `Mods=`
list, so for per-player stats the mod must be on the Workshop (clients then
auto-download it on next launch). This has to be done from a machine with
Project Zomboid + Steam installed (not the server).

## 1. Build the Workshop upload folder

On your PC, create this under your Zomboid user dir
(`~/Zomboid/` on Linux/Mac, `%USERPROFILE%\Zomboid\` on Windows):

```
Zomboid/Workshop/ZombiStatsExporter/
  workshop.txt          <- copy from priv/pz_mods/workshop.txt
  preview.png           <- any 256x256-ish PNG (required by the uploader)
  Contents/
    mods/
      ZombiStats/        <- copy the whole priv/pz_mods/ZombiStats/ folder here
        42.0/
          mod.info
          media/lua/server/ZombiStats.lua
```

## 2. Upload from the game

1. Launch Project Zomboid → main menu **Workshop** → **Create and Upload**
   (or **Steam Workshop** → it lists items found in `Zomboid/Workshop/`).
2. Select **ZombiStatsExporter**, review the title/description, set visibility,
   accept the Steam Workshop agreement, and **Upload**.
3. Steam opens the new item's page. Copy its **Workshop ID** (the number in the
   URL, `…?id=XXXXXXXXXX`).

## 3. Tell the panel maintainer the Workshop ID

Then the server gets, on the active `<servername>.ini`:

- `WorkshopItems=` … `;<that-id>`
- `Mods=` … `;ZombiStats`

and a restart. Clients auto-download on next launch; the panel's Players tab
fills in automatically once the mod is active.
