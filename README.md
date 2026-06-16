# Zombi

A password-protected Phoenix LiveView control panel for a Project Zomboid
dedicated server. Tabs:

- **Control** — restart the server (`docker compose restart`), with a "safe to
  restart" indicator showing who's online (via RCON) so you don't kick players,
  plus pending workshop mod updates (the cause of "can't join, mod mismatch").
- **Resources** — live host CPU (per core) and memory graphs (via `os_mon`),
  plus live players / loaded-zombie count from the server-side mod.
- **Players** — persisted per-player stats (kills, hours survived, health, last
  seen) with a kill-trend graph each, and an activity feed (join/leave/death).
- **Mods** — full installed-mod table with Steam Workshop links and the active
  game build version.
- **Logs** — live `docker logs` stream (last 500 lines), color-coded by level.

## Stack

Phoenix 1.8 + LiveView. Auth is HTTP Basic. Persistent stats are stored in
SQLite via **Ash** (the `Zombi.Stats` domain: `Player`, `PlayerSnapshot`,
`ServerEvent`), so player history and the activity feed survive restarts. Game
stats come from a small server-side Lua mod (`priv/pz_mods/ZombiStats`) that
writes JSON the app reads; see [Server-side mod](#server-side-mod).

## Configuration

All runtime config comes from environment variables (see `config/runtime.exs`):

| Variable | Purpose | Default |
|---|---|---|
| `AUTH_USERNAME` | Basic auth username | `admin` |
| `AUTH_PASSWORD` | Basic auth password | `changeme` |
| `PZ_COMPOSE_DIR` | Dir containing the Zomboid `docker-compose.yml` | `.` |
| `PZ_SERVER_NAME` | Server config name (`<name>.ini`) | `servertest` |
| `PZ_CONTAINER` | Zomboid container name (for logs / version) | `projectzomboid` |
| `RCON_HOST` / `RCON_PORT` / `RCON_PASSWORD` | RCON connection for the player list | `127.0.0.1` / `27015` / – |
| `SSL_CERT_PATH` / `SSL_KEY_PATH` / `SSL_PORT` | Enable native HTTPS when set | – / – / `443` |
| `SECRET_KEY_BASE` | Phoenix secret (`mix phx.gen.secret`) | required in prod |
| `DATABASE_PATH` | SQLite file path | required in prod |
| `PORT` | HTTP port | `4000` |

The app reads the server's workshop manifest
(`<PZ_COMPOSE_DIR>/server-files/steamapps/workshop/appworkshop_108600.acf`) and
active config (`<PZ_COMPOSE_DIR>/server-data/Server/<PZ_SERVER_NAME>.ini`), so it
must run on the same host as the Zomboid server with read access to those files
and reachability to RCON and the docker socket.

## Local development

```bash
mix setup            # deps, db, assets
mix phx.server       # http://localhost:4000
```

Basic auth uses the defaults above unless you export `AUTH_PASSWORD` etc.

## Deployment

Native Elixir release, copied to the server over ssh. One command:

```bash
bin/deploy.sh                 # full build + deploy
bin/deploy.sh --config-only   # only push config/runtime.exs and restart
```

The script builds a prod release, packages it, scp's it to the server, and swaps
it in behind systemd. Override the target with env vars:

```bash
DEPLOY_HOST=root@1.2.3.4 DEPLOY_DIR=/opt/zombi SERVICE=zombi bin/deploy.sh
```

The script builds a prod release, packages it, scp's it to the server, swaps it
in behind systemd, and runs database migrations (`Zombi.Release.migrate()` via
`bin/zombi rpc` on the live node). New migrations are generated with
`mix ash.codegen <name>` after changing Ash resources.

The build host and server must share OS/arch (the release bundles the Erlang
runtime). Current target: Ubuntu 24.04 x86_64.

### Server setup (one-time)

The deploy script assumes this already exists on the server:

- **Release dir** `/opt/zombi`, owned appropriately, writable by the deploy user.
- **systemd unit** `/etc/systemd/system/zombi.service`:

  ```ini
  [Unit]
  Description=Zombi - Project Zomboid control panel
  After=network.target docker.service
  Wants=docker.service

  [Service]
  Type=simple
  EnvironmentFile=/etc/zombi/zombi.env
  ExecStart=/opt/zombi/bin/zombi start
  ExecStop=/opt/zombi/bin/zombi stop
  Restart=on-failure
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  ```

  Then `systemctl daemon-reload && systemctl enable --now zombi`.

- **Env file** `/etc/zombi/zombi.env` (`chmod 600`) with the variables above,
  including `PHX_SERVER=true`.
- **TLS:** the panel sends the basic-auth password, so run it over HTTPS. Either
  set `SSL_CERT_PATH`/`SSL_KEY_PATH` to a cert (self-signed is fine for an IP) for
  native HTTPS, or front it with a reverse proxy that terminates TLS and sets
  `x-forwarded-proto` (the prod config already trusts that header).

  Self-signed cert for an IP:
  ```bash
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/zombi/key.pem -out /etc/zombi/cert.pem -days 3650 \
    -subj "/CN=<IP>" -addext "subjectAltName=IP:<IP>"
  ```

The Zomboid server must have RCON enabled (`RCONPort`/`RCONPassword` in its
server `.ini`); binding RCON to `127.0.0.1` is recommended since the panel runs
on the same host.

For a domain, the simplest TLS is a reverse proxy: Caddy with
`zombi.example.com { reverse_proxy 127.0.0.1:4000 }` gets and renews a
Let's Encrypt cert automatically; bind the app to loopback and leave `SSL_*`
unset.

## Server-side mod

`priv/pz_mods/ZombiStats/` is a server-side-only Project Zomboid mod (B42
layout). Every few seconds it writes `<data-dir>/Lua/zombi-stats.json` with the
online players (name, kills, hours survived, health) and loaded-zombie count,
and appends a line to `Lua/zombi-events.json` on each player death. The app
reads these files; `Zombi.StatsIngester` persists them via the `Zombi.Stats`
domain on a timer.

Because it's server-side only (no client content), **connecting players don't
need to install or download anything**. To install:

1. Copy the folder to `<PZ_COMPOSE_DIR>/server-data/mods/ZombiStats/`.
2. Add `ZombiStats` to the `Mods=` line in the server `.ini` (not
   `WorkshopItems=` — it's local).
3. Restart the Zomboid server so it loads.
