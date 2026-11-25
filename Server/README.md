# TodayFlow Sync Server

The central database that TodayFlow devices sync with. Each device keeps its
own local database and works offline; this server holds the shared copy.

Design: [`../docs/sync/PLAN.md`](../docs/sync/PLAN.md). Status and next steps:
[`../docs/sync/HANDOFF.md`](../docs/sync/HANDOFF.md).

TodayFlow 1.9.26 and later pair with it in Settings ▸ Sync.

## What runs

| Service | Image | Job |
|---|---|---|
| `server` | built from this folder | HTTP API on port 8787 |
| `db` | `postgres:17-alpine` | the database |
| `backup` | `postgres:17-alpine` | `pg_dump` daily into `backups/`, newest 14 kept |

Data lives under `DATA_DIR`:

```
DATA_DIR/postgres/   database files
DATA_DIR/blobs/      attachment files, by SHA-256
DATA_DIR/backups/    nightly dumps
```

## Install on TrueNAS SCALE with deploy.sh (no Docker access needed on the NAS)

The NAS doesn't need to build images: the binary is built on a Mac and runs
in a stock `ubuntu:22.04` container as the TrueNAS custom app `todayflow`.

1. On the NAS, create a dataset for TodayFlow (for example `tank/todayflow`)
   with folders `app/`, `postgres/` (owner uid 70), `blobs/` and `control/`
   (owner uid 10001), and a folder for dumps, ideally on another disk. Add an
   hourly snapshot task for the dataset.
2. On the Mac: `cp deploy.env.example deploy.env` and fill it in (SSH login,
   dataset folder, dumps folder). `deploy.env` is ignored by git: keep your
   NAS's addresses and paths there, never in the source.
3. Run `./deploy.sh`. It builds the binary, copies it with `backup.sh`,
   `truenas-install.py` and `deploy.env` to `<dataset>/app/`, and creates or
   updates the app through `midclt`, so it shows in Apps.

Secrets are generated on the NAS on first run in `app/secrets.env` (mode 600)
and reused afterwards; the admin page password is there. Users' pairing codes
are made on the admin page and never stored in clear. Run `./deploy.sh` again
to update; the previous binary is kept as `app/TodayFlowServer.prev`.

## Install on TrueNAS SCALE (generic, with a shell that can run Docker)

1. **Datasets.** In Datasets, create `todayflow` under your pool (for example
   `tank/apps/todayflow`). Under Data Protection, add a periodic snapshot task
   for it (hourly, keep 2 weeks is plenty).
2. **Files.** Copy this `Server/` folder into the dataset, for example
   `/mnt/tank/apps/todayflow/server`. In that folder, copy `.env.example` to
   `.env` and set:
   - `POSTGRES_PASSWORD`: a long random string (`openssl rand -hex 24`)
   - `TODAYFLOW_ADMIN_PASSWORD`: password for the admin page (at least 12 characters)
   - `DATA_DIR=/mnt/tank/apps/todayflow/data`
3. **Folder owner.** The server runs as user id 10001:
   `mkdir -p /mnt/tank/apps/todayflow/data/blobs && chown 10001 /mnt/tank/apps/todayflow/data/blobs`
4. **Start.** In a TrueNAS shell:
   ```
   cd /mnt/tank/apps/todayflow/server
   docker compose up -d --build
   ```
   The first build takes several minutes. Alternatively use Apps ▸ Discover ▸
   ⋮ ▸ Install via YAML, but then `build:` must be replaced by a prebuilt image.
5. **Check.** `curl http://<nas-address>:8787/health` → `ok`.
6. **Outside the LAN.** Install Tailscale from the TrueNAS app catalog and use
   `tailscale serve --bg 8787` on the NAS to get
   `https://<nas-name>.<tailnet>.ts.net`, with a real certificate and no open
   ports. Use that address in the app.

## Run on a Mac (development)

```
cp .env.example .env     # set both secrets
docker compose up -d --build
curl http://localhost:8787/health
```

## Users and security

Each user has their own data. A device pairs with **its user's pairing code**
and from then on can only read and write that user's rows and files.

- **Pairing codes** are 96 random bits (`xxxxxx-xxxxxx-xxxxxx-xxxxxx`, hex), shown
  once when made, stored only as a hash. A new code replaces the old one;
  devices already paired keep working.
- **Device tokens** are 256 random bits, stored only as a hash, sent as
  `Authorization: Bearer …`. Signing a device out stops it at once.
- **Wrong codes / passwords**: 1 s delay each; after 10 wrong pairing codes
  (5 wrong admin passwords) in 10 minutes, that door closes for 10 minutes.
- **Files** are stored once on disk, but each user only sees files they
  uploaded themselves; another user's file looks exactly like a missing one,
  and claiming a file requires sending its exact bytes.
- **Not encrypted at rest**: anyone with admin access to the NAS can read the
  database. Traffic on port 8787 is plain HTTP on the LAN; use Tailscale
  HTTPS (`tailscale serve`) for anything beyond the home network.

## Admin page

`http://<nas>:8788` — sign in with `TODAYFLOW_ADMIN_PASSWORD`.

| Page | What you can do |
|---|---|
| Overview | users, active devices, synced rows, files, last backup, uptime |
| Users | add a user (shows their pairing code once), new pairing code, delete a user (type the name to confirm) |
| Devices | every device by user, when paired and last seen; sign a device out |
| Backups | list dumps, download one, **Back up now** |

The page has its own port so it can stay on the home network: **do not share
port 8788 through Tailscale or a router.** Sessions last 12 hours and end
when the server restarts. Every change is a POST with a per-session token and
a SameSite=Strict cookie; pages send a strict Content-Security-Policy.

The same actions exist as commands:

```
TodayFlowServer adduser <name>           # prints the pairing code
TodayFlowServer users
TodayFlowServer resetcode <name>
TodayFlowServer deluser <name> --yes
TodayFlowServer devices [user]
TodayFlowServer revoke <device id|name>
```

## Restore a backup

```
docker compose exec -T db pg_restore -U todayflow -d todayflow --clean < $DATA_DIR/backups/<file>.dump

# Installed with deploy.sh (NAS shell, as an admin; the admin page shows this
# command with your dumps folder filled in):
sudo docker exec -i $(sudo docker ps -qf name=todayflow-db) pg_restore -U todayflow -d todayflow --clean \
  < <dumps folder>/<file>.dump
```

Attachment files in `blobs/` are not in the dump; dataset snapshots cover them.

## API

All `/v1` routes except `/v1/pair` need `Authorization: Bearer <token>`.

| Route | Purpose |
|---|---|
| `GET /health` | `ok` when running |
| `POST /v1/pair` | `{pairingCode, deviceName}` (a user's code) → `{deviceId, token}`; 401 wrong code, 429 locked |
| `GET /v1/status` | `{ok, records, latestSeq, deviceId}` |
| `POST /v1/push` | `{changes:[{entity,id,op,changedAt,data}]}` → per change `accepted` or `stale` (+ the newer copy). Max 1000 changes, 16 MB. Changes dated more than 10 min in the future are refused (device clock check). |
| `GET /v1/pull?since=N&limit=M` | Changes after `N`, oldest first, without the caller's own; `next` is the cursor, `more` says if another page waits |
| `PUT /v1/blobs/{sha256}` | Upload a file (max 1 GB); 201 new, 200 already stored, 400 if bytes do not match the hash |
| `HEAD /v1/blobs/{sha256}` | 200 stored, 404 not |
| `GET /v1/blobs/{sha256}` | Download |
| `GET /v1/obsidian/status` | Obsidian proxy: the plugin's status (see below) |
| `GET`/`PUT`/`DELETE /v1/obsidian/vault/{path}` | Obsidian proxy: read, list (path ending `/`), write, delete a note |
| `POST /v1/obsidian/open/{path}` | Obsidian proxy: show a note in Obsidian |

### Obsidian proxy

A paired Mac can reach the Obsidian **Local REST API** plugin through this
server, for an Obsidian the Mac cannot reach itself (for example away from
home, when the server is reachable over Tailscale). The Mac names the plugin on
each request with `X-Obsidian-Target: https://<host>:27124` (the address as
the *server* sees it) and `X-Obsidian-Authorization: Bearer <plugin key>`.
Nothing is stored on the server. Only `/`, `/vault/…` and `/open/…` are
forwarded, and only with a valid device token. The plugin's self-signed
certificate is accepted. A key Obsidian rejects comes back as 403 (401 always
means the device token); an unreachable plugin is 502. In the app: Settings ▸
Obsidian ▸ Remote ▸ Transport **TodayFlow server**.

Conflicts: the change with the later `changedAt` wins for the whole row.

## Settings (`.env`)

| Variable | Default | Meaning |
|---|---|---|
| `POSTGRES_PASSWORD` | required | database password |
| `TODAYFLOW_ADMIN_PASSWORD` | unset = admin page off | admin page password, ≥ 12 chars |
| `ADMIN_PORT` | `8788` | admin page port |
| `TODAYFLOW_OBSIDIAN_PROXY` | on | `off` turns the `/v1/obsidian` proxy off |
| `TODAYFLOW_BACKUP_DIR` / `TODAYFLOW_CONTROL_DIR` | unset | dumps folder (read) and "back up now" folder (shared with the backup service) |
| `TODAYFLOW_ADMIN_SECURE_COOKIE` | `0` | `1` when the admin page is served over HTTPS |
| `DATA_DIR` | `./data` | where data, files and backups live |
| `PORT` | `8787` | port on the host |
| `BACKUP_EVERY_SECONDS` | `86400` | dump interval |
| `BACKUP_KEEP` | `14` | dumps kept |
| `PGSSLMODE` | `disable` | `require` when Postgres is on another machine |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warning`, `error` |

## Tests

Need a Postgres to talk to:

```
docker run -d --name todayflow-test-pg -e POSTGRES_USER=todayflow \
  -e POSTGRES_PASSWORD=test -e POSTGRES_DB=todayflow -p 55432:5432 postgres:17-alpine
TEST_PGPORT=55432 swift test
docker rm -f todayflow-test-pg
```

Without `TEST_PGPORT` the suite is skipped, not passed.
