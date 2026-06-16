# Zombi

A small Phoenix LiveView control panel for a Project Zomboid dedicated server.
Single password-protected page that lets trusted users:

- **Restart the server** (`docker compose restart` on the host).
- **See pending workshop mod updates** — which mods have a newer version on
  Steam than the server has installed (the cause of "can't join, mod version
  mismatch"). A restart re-pulls them.
- **See who's online** via RCON, with a clear "safe to restart" indicator so
  you don't kick players mid-game.

## Stack

Phoenix 1.8 + LiveView, no database use for the feature (Ash/SQLite are present
from the generator but the panel itself is stateless). Auth is HTTP Basic.

## Configuration

All runtime config comes from environment variables (see `config/runtime.exs`):

| Variable | Purpose | Default |
|---|---|---|
| `AUTH_USERNAME` | Basic auth username | `admin` |
| `AUTH_PASSWORD` | Basic auth password | `changeme` |
| `PZ_COMPOSE_DIR` | Dir containing the Zomboid `docker-compose.yml` | `.` |
| `PZ_SERVER_NAME` | Server config name (`<name>.ini`) | `servertest` |
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
