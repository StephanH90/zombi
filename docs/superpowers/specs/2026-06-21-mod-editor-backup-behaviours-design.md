# Mod-list editor, one-click backup, and dev/test behaviours

## Context

Zombi is a Phoenix/LiveView control panel for a Project Zomboid (PZ) dedicated
server. Today it runs **only on the gameserver host**: it shells out to docker,
reads PZ's files, and talks RCON. Two operator tasks still require SSH-ing into
the box and hand-editing files:

1. **Editing the mod list** — PZ activates mods via two lines in the server
   `.ini`: `WorkshopItems=` (numeric Steam Workshop IDs) and `Mods=` (internal
   mod-id strings). Editing means opening the ini, fiddling with both lines, and
   restarting.
2. **Backing up** — there is a `backup.sh` on the server, but it must be run by
   hand over SSH with no feedback.

This work adds both to the web UI, and — because the app currently can't run
anywhere but the gameserver — introduces **config-driven behaviours** so the app
runs locally (and under test) against fakes. Outcome: manage mods and trigger
backups from the browser, and develop/test the whole thing on a laptop.

## Decisions (settled during brainstorming)

- **Mod-id resolution:** paste a Workshop link → app scrapes the Workshop page
  for `Mod ID:` / `Workshop ID:` → user **confirms** the detected ids before
  activating. (A workshop item can contain several mod-ids; order matters.)
- **Backup output:** timestamped `.tar.gz` of `server-data/Saves` + the server
  `.ini`, written to a `backups/` dir on the host. UI lists past backups
  (name/size/date), supports **download** (browser) and delete.
- **Backup progress:** **phase + percent** (Preparing → Archiving(live %) →
  Done), streamed over PubSub.
- **Behaviour scope:** the new feature's IO **plus** the existing `GameServer`
  (docker restart/version). prod/runtime use real impls; dev + test use fakes,
  so the local UI fully works off-host.
- **Modeling:** use **Ash resources** to model the domain (per user request),
  with the behaviours underneath doing the actual IO. `Mod` = Simple data layer
  (generic actions only, "model behaviour"); `Backup` = `Ash.DataLayer.Ets`
  (in-memory run tracking).
- **No new SQLite tables / migrations.** Mod list and backups are
  filesystem-truth; Simple and ETS data layers need no `ash.codegen`.

## Architecture

Three layers, top to bottom:

1. **Web (LiveView):** `ModsLive` (extended), new `BackupLive`, a
   `BackupController` for downloads.
2. **Domain (Ash):** `Zombi.Mods.Mod` (Simple), `Zombi.Backups.Backup` (ETS),
   exposed via domain code interfaces. Actions hold the business logic and call
   the behaviours.
3. **Behaviours (IO, config-swappable):** dispatch module + real impl + fake
   impl, selected via `Application.get_env` (the codebase's existing no-Mox
   convention).

### Behaviours

| Dispatch module | Callbacks | Real impl | Fake impl |
|---|---|---|---|
| `Zombi.GameServer` | `restart/0`, `version/0` | `.Docker` (current `game_server.ex` body moved here) | `.Fake` |
| `Zombi.ModConfig` | `read_mods/0`, `write_mods/1` | `.File` (read/write the ini) | `.Fake` (Agent, seeded sample mods) |
| `Zombi.WorkshopClient` | `fetch_mod_info/1` | `.Steam` (Req fetch + scrape) | `.Fake` (canned) |
| `Zombi.Backup` | `archive/1` (with `on_progress` callback) | `.Tar` (tar `--checkpoint`) | `.Fake` (simulated phases) |

Dispatcher pattern:

```elixir
defmodule Zombi.ModConfig do
  @callback read_mods() :: {:ok, %{workshop_ids: [String.t()], mod_ids: [String.t()]}} | {:error, term}
  @callback write_mods(%{workshop_ids: [String.t()], mod_ids: [String.t()]}) :: :ok | {:error, term}
  def impl, do: Application.get_env(:zombi, :mod_config, Zombi.ModConfig.File)
end
```

`Zombi.GameServer` stays the dispatcher so existing callers
(`server_live.ex`, `mods_live.ex`) are **unchanged**; it keeps a
`defdelegate parse_version/1, to: Zombi.GameServer.Docker` so the existing test
stays green.

Config:
- `config/config.exs` — defaults to **real** impls (`.Docker`, `.File`,
  `.Steam`, `.Tar`) + `backups_dir`.
- `config/dev.exs` and `config/test.exs` — **fakes**.
- `config/runtime.exs` — add `backups_dir` env (`PZ_BACKUPS_DIR`, default
  `<compose_dir>/backups`).

### Mods domain (`Zombi.Mods`, file `lib/zombi/mods.ex`)

`Zombi.Mods.Mod` — Simple data layer, **generic actions only**:

- `list` → `{:array, :struct}` (`items: [instance_of: __MODULE__]`) built from
  `ModConfig.read_mods/0`.
- `resolve_link` (arg `link`) → `:map` `%{workshop_id, title, mod_ids}` via
  `Workshop.url_to_id/1` + `WorkshopClient.fetch_mod_info/1`.
- `activate` (args `workshop_ids`, `mod_ids`) → `ModConfig.write_mods/1` then
  `GameServer.restart/0`.

Impl modules mirror the existing `Zombi.Stats.Player.Ingest`
(`use Ash.Resource.Actions.Implementation`). Domain code interfaces:
`list_mods`, `resolve_link`, `activate_mods`. `AshPhoenix` extension + a
`forms do form :resolve_link, args: [:link] end` block back the add-mod form.

**add/remove are staged in the LiveView**, not actions: load list → stage
removals/additions in assigns → single `activate` writes both ini lines (dedupe,
preserve order) and restarts.

### Backups domain (`Zombi.Backups`, file `lib/zombi/backups.ex`)

`Zombi.Backups.Backup` — `Ash.DataLayer.Ets`, `ets do private? false end` (shared
across the runner Task and LiveViews). Attributes: `name`, `status`
(`:preparing|:archiving|:done|:failed`), `phase`, `percent`, `size`, `path`,
timestamps. Actions: `start` (create — inserts the row), `progress` (update,
`require_atomic? false`), `refresh` (generic — scan `backups/` dir, upsert
`:done` rows), `read`, `destroy` (also `File.rm` the tar via after-action hook).
Code interfaces: `start_backup`, `update_backup`, `refresh_backups`,
`read_backups`, `delete_backup`.

### Backup runner

`Zombi.Backups.Runner` driven by a `{Task.Supervisor, name: Zombi.BackupTaskSupervisor}`
added to `application.ex`. Spawned **from the LiveView** after `start_backup!`
returns (keeps the Ash action pure). Flow: set Preparing → call
`Zombi.Backup.impl().archive(on_progress: fn pct -> ... end)` (best-effort RCON
`save` first) → update ETS + broadcast on each integer-percent change → Done /
Failed.

**Percent math:** GNU tar `--checkpoint=N` fires every N records (512 bytes
each). `bytes ≈ checkpoint_no × N × 512`; `percent = min(100, round(bytes × 100 / total_uncompressed))`,
where `total_uncompressed` is precomputed (sum of `Saves` + ini sizes). Pure
helper `Zombi.Backup.Tar.percent_for/3` is unit-tested. tar output is read via a
`Port` (mirrors `LogCollector`). PubSub topics: `"backup:#{id}"` (per-run
progress) and `"backups"` (list changed).

### Web layer

- `lib/zombi_web/live/mods_live.ex` (extend `/mods`): keep the version card +
  Steam-update table; add an editor — active-mods list with remove buttons, an
  "Add by Workshop link" `AshPhoenix.Form` (`resolve_link`), a confirm panel
  listing scraped mod-ids (checkboxes), and an Activate button
  (`start_async` → `activate_mods`).
- `lib/zombi_web/live/backup_live.ex` (new `/backup`): create button, in-progress
  card with phase + percent progress bar, table of past backups (download/delete).
  Subscribes to `"backups"` + the active run topic.
- `lib/zombi_web/controllers/backup_controller.ex` (new): `download/2` →
  `send_download {:file, path}`, validated against tracked backups (no traversal).
- `lib/zombi_web/router.ex`: `live "/backup"` + `get "/backups/:id/download"`
  inside the basic-auth `:browser` scope.
- `lib/zombi_web/components/layouts.ex`: add a `Backup` tab (`@active == :backup`).

## Testing (TDD)

Pure functions first (fast, `async: true`, mirror `workshop_test.exs`):
- ini `parse_mods_line/1` + `render_mods_lines/2` round-trip (dedupe, order,
  append-if-missing, leave other lines untouched).
- `Workshop.url_to_id/1` (query param, full URL, invalid).
- `WorkshopClient.Steam.parse_mod_ids/1` against a saved HTML fixture.
- `Backup.Tar.percent_for/3` (zero, monotonic, clamp 100, total==0).

Ash action tests with fakes (`Application.put_env` + `on_exit` restore; ETS rows
cleared between tests; `:backups_dir` → ExUnit `tmp_dir`):
- `Zombi.Mods`: `list_mods`, `activate_mods` (assert write + restart via
  recording fake).
- `Zombi.Backups`: `start_backup` row state, `update_backup` progression,
  `refresh_backups` picks up a file, `delete_backup` removes the file.

LiveView tests (`ConnCase` + `auth_header/1`, like `server_live_test.exs`):
- `/mods`: list renders, add-link form → confirm panel shows fake mod-ids,
  activate → flash.
- `/backup`: renders, create with `Backup.Fake` → progress card → Done row;
  plus an auth-rejection test.

## Build sequence (parallelizable)

Foundation (independent, parallel subagents):
- **A.** Behaviours + `GameServer` refactor (`.Docker`/`.Fake`) + config keys.
- **B.** `ModConfig` + `.File` (`parse_mods_line`/`render_mods_lines`) + `.Fake` + tests.
- **C.** `WorkshopClient` + `.Steam` (`url_to_id`, `parse_mod_ids`) + `.Fake` + fixture + tests.
- **D.** `Backup` + `.Tar` (`percent_for`) + `.Fake` + tests.

Domain (needs A–D):
- **E.** `Zombi.Mods` domain + `Mod` resource + impls; register in `ash_domains`.
- **F.** `Zombi.Backups` domain + `Backup` ETS resource + `Refresh` + `Runner`;
  `Task.Supervisor` in `application.ex`; register in `ash_domains`.

Web (needs E/F):
- **G.** `mods_live.ex` editor + tests.
- **H.** `backup_live.ex` + `BackupController` + router + tabs + tests.

Final: **I.** `mix compile --warnings-as-errors`, `mix test`, `mix format`.

## Risks / gotchas

- **Ash:** Simple layer = generic actions only (no `create/read`); ETS layer
  needs `private? false` for cross-process sharing and is **not** in the SQL
  sandbox (clean rows manually in tests). Spawn the runner from the LiveView,
  not an `after_action`, to avoid a read-before-commit race. Forms on generic
  actions need the `forms` block to map positional args.
- **PZ:** `Mods=` order is load order and matters — dedupe preserves first
  occurrence. Scraping is fragile (author-written description) → user confirms;
  handle empty scrape gracefully ("enter manually"). Rewrite **only** the two
  ini lines (atomic temp-write+rename), never the whole file. Activate restarts
  the server (kicks players).
- **Backup:** RCON `save` and tar over a live `Saves` dir are best-effort;
  percent is approximate (clamp 100). `tar`/`du` must be on PATH on the host
  (fakes avoid this in dev).
