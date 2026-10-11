# Windmill v1 Scripts, Flows and Internal Apps — Railway template spec

## Listing

- **Name:** Windmill v1 Scripts, Flows and Internal Apps (version label `v1` = major of the pinned release `v1.830.0`; Windmill tags its releases with a `v` prefix)
- **Description (79 chars):** Turn Python and TS scripts into workflows, UIs and cron jobs. Scalable workers.
- **Category:** Automation
- **Tags:** windmill, workflow, automation, scripts, internal-tools, cron, python, typescript

The description is delivered as written: scripts become flows, auto-generated UIs and schedules, and the default worker pool scales with Railway replicas. No wording change needed.

## Base market template

- **Base: `UI371k` ("Windmill", 227 projects / 30 active).** The only market template with the upstream topology: server, default worker, native worker, LSP, a Caddy path proxy and Postgres. Kept: the service split, the separate native worker group, the idea of a Caddy front proxy for `/ws/*`. Replaced: everything that is unpinned, public-by-accident or deprecated (see Improvements).
- **`windmill` ("Windmill (Open-Source Automation & Workflow Orchestration Platform)", 65 projects):** server + one worker on `:latest`, Postgres 17. Taken: `BASE_URL` from the public domain. Rejected: `WM_ADMIN_USERNAME` / `WM_ADMIN_PASSWORD=admin` (not referenced anywhere in the windmill-labs/windmill repository, GitHub code search 2026-10-10, so they do nothing), no native worker, no LSP, no healthchecks. Its README was not used.
- **`windmill-1` ("Windmill", 9 projects):** one container built from `Pluma-Negra/windmill-railway` (`windmill-full:1.662`, server and worker in one process). Rejected: no worker scaling, stale image, repo has no license.
- **`_upstream` license status:**
  - `rconjoe__wmprox` — MIT, "Copyright (c) 2023 Railway". Its Caddy global-options pattern was adapted for `services/proxy/Caddyfile` (credited in NOTICE.md).
  - `Pluma-Negra__windmill-railway` — no license (GitHub API returns none). Read for ideas only; nothing copied.

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| Windmill | `ghcr.io/windmill-labs/windmill` | `1.830.0` (git tag `v1.830.0`) | 2026-10-09 | 2026-10-10 |
| Windmill Worker | `ghcr.io/windmill-labs/windmill` | `1.830.0` | 2026-10-09 | 2026-10-10 |
| Windmill Native Worker | `ghcr.io/windmill-labs/windmill` | `1.830.0` | 2026-10-09 | 2026-10-10 |
| Windmill Extra | `ghcr.io/windmill-labs/windmill-extra` | `1.830.0` | 2026-10-09 | 2026-10-10 |
| Proxy | repo `services/proxy` → `caddy` (Docker Official Image) | `2.11.7-alpine` | 2026-10-03 (Caddy v2.11.7) | 2026-10-10 |
| Admin Bootstrap | repo `services/admin-bootstrap` → `curlimages/curl` | `8.22.0` | 2026-09-02 (image push) | 2026-10-10 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` (Railway-maintained major tag) | n/a | 2026-10-10 |

All tags were confirmed to exist in their registries on 2026-10-10. Keep the three `windmill` services and `windmill-extra` on the **same** version. `ghcr.io/windmill-labs/windmill-lsp` is no longer versioned (last numbered tag `1.603.x`); upstream replaced it with `windmill-extra`.

## Architecture

```
                    Internet (HTTPS via Railway edge)
                                 |
                       +---------v----------+
                       |   Proxy (Caddy)    |  only public service, :8080
                       +----+----------+----+
     /ws/* /ws_debug/* /ws_mp/*        |  all other paths
                            |          |
           +----------------v--+   +---v--------------------+
           | Windmill Extra    |   | Windmill (MODE=server) |  :8000
           | gateway :3000     |-->| UI, REST API, webhooks |
           | LSP + debugger    |   | runs DB migrations     |
           +-------------------+   +-----------+------------+
             (fetches debug signing keys)      |        ^
                                               v        | one-shot, /api
 +------------------------+          +-----------------+ +-----------------+
 | Windmill Worker  x3    |--------->|    Postgres     | | Admin Bootstrap |
 | default group          |  job     | postgres-ssl:18 | +-----------------+
 +------------------------+  queue   | + volume        |
 +------------------------+          |                 |
 | Windmill Native Worker |--------->|                 |
 | native group, 8 workers|          +-----------------+
 +------------------------+

 Everything below the Proxy talks over Railway private networking (*.railway.internal).
```

- Only **Proxy** has a public domain. Postgres, the server and the extra gateway have no public domain and no TCP proxy.
- Workers do not need to reach the server: Windmill's job queue lives in Postgres, and each worker process starts its own local API endpoint for the jobs it executes (`run_server` in worker mode, bound to 127.0.0.1).
- Upstream components intentionally **not** included:
  - `windmill_indexer` (full-text job/log search): Enterprise Edition only, `replicas: 0` upstream.
  - Multiplayer (`/ws_mp/*`): Enterprise Edition only; `ENABLE_MULTIPLAYER=false`. The route exists in the proxy so an EE licence holder only has to flip the variable.
  - `windmill_worker_reports` (Chromium worker group): commented out upstream.
  - Docker socket / Docker-in-Docker for `# docker` jobs: commented out upstream, and not possible on Railway. Upstream's `# sandbox <image>` runtime relies on nsjail, which needs privileges Railway does not grant.
  - SMTP listener on port 2525 (email triggers) via `caddy-l4` on port 25: Railway has no public port 25, and a TCP proxy on a random port is not usable as a mail exchanger.

## Services

### Proxy
- Source: repo `baranberkay96/windmill-railway`, root `/services/proxy` (Dockerfile `FROM caddy:2.11.7-alpine`, `caddy validate` at build)
- Start command: image default (`caddy run --config /etc/caddy/Caddyfile`); pre-deploy: none
- Healthcheck: `/__proxy/health` (answered by Caddy itself), timeout 120 s
- Public domain: yes, target port 8080; TCP proxy: none; volume: none
- Restart: ALWAYS; replicas: 1; cron: none
- Routing: `/ws/*`, `/ws_debug/*`, `/ws_mp/*` → Windmill Extra; everything else → Windmill server. WebSocket upgrades and SSE pass through Caddy's `reverse_proxy` without extra config.

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port Caddy listens on; the public domain and the healthcheck target it. |
| `WINDMILL_SERVER_UPSTREAM` | `${{Windmill.RAILWAY_PRIVATE_DOMAIN}}:${{Windmill.PORT}}` | Private address of the Windmill server. |
| `WINDMILL_EXTRA_UPSTREAM` | `${{Windmill Extra.RAILWAY_PRIVATE_DOMAIN}}:${{Windmill Extra.PORT}}` | Private address of the windmill-extra gateway. |

### Windmill
- Source: image `ghcr.io/windmill-labs/windmill:1.830.0`
- Start command: image default (`windmill`, mode from `MODE`); pre-deploy: none (the server runs database migrations itself on start)
- Healthcheck: `/api/health/status`, timeout 600 s (first boot applies every migration). Unauthenticated; returns 503 only when the database is unreachable and 200 when healthy or "degraded" (no worker alive yet), so the server can go green before workers.
- Public domain: no; TCP proxy: none; volume: none
- Restart: ALWAYS (upstream uses `restart: unless-stopped`); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `MODE` | `server` | API server and UI only; jobs run on the worker services. |
| `PORT` | `8000` | HTTP port (Proxy and healthcheck use it). |
| `SERVER_BIND_ADDR` | `::` | Bind on all IPv6/IPv4 interfaces (default would be `0.0.0.0`, IPv4 only). |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}?sslmode=disable` | Postgres over the private network, TLS off as in upstream `.env`. |
| `BASE_URL` | `https://${{Proxy.RAILWAY_PUBLIC_DOMAIN}}` | Public URL; Instance settings > Base URL overrides it once saved. |
| `RUST_LOG` | `info` | Log level. |

### Windmill Worker
- Source: image `ghcr.io/windmill-labs/windmill:1.830.0`
- Start command: image default; pre-deploy: none
- Healthcheck: none (no HTTP listener reachable from outside the container)
- Public domain: no; TCP proxy: none; **volume: none** (see cache note)
- Restart: ALWAYS; **replicas: 3** (upstream compose default); cron: none
- Cache note: upstream mounts a `worker_dependency_cache` volume at `/tmp/windmill/cache`. Here each replica keeps that cache on its own ephemeral disk because (a) replicas cannot have volumes and (b) Railway mounts volumes empty, so a volume at that path would hide the Python runtimes and Go build cache the image pre-installs there. Effect: after every redeploy or new replica, the first run of a script with new dependencies re-downloads them (uv/bun are fast, but expect extra seconds per first run). Windmill EE offers an S3-backed shared dependency cache; not configured here.

| Variable | Value | Description |
|---|---|---|
| `MODE` | `worker` | Job worker only. |
| `WORKER_GROUP` | `default` | Worker group; its tags come from the Workers page config. |
| `NUM_WORKERS` | `1` | Windmill forces 1 outside native mode (`I_ACK_NUM_WORKERS_IS_UNSAFE` overrides; not recommended). Scale with replicas. |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}?sslmode=disable` | Postgres; the job queue lives there. |
| `BASE_URL` | `https://${{Proxy.RAILWAY_PUBLIC_DOMAIN}}` | Used in links jobs generate (approval/resume URLs). |
| `FAVOR_UNSHARE_PID` | `true` | Upstream setting. PID-namespace isolation per job when the kernel allows it; otherwise Windmill logs a warning and runs jobs without isolation. |
| `RUST_LOG` | `info` | Log level. |

`WORKER_TAGS` is deliberately unset so the group's tags stay editable in the UI. `DISABLE_NSJAIL` is unset (nsjail is off by default in this version and needs privileges Railway does not grant). `KEEP_JOB_DIR` stays at its default `false`.

### Windmill Native Worker
- Source: image `ghcr.io/windmill-labs/windmill:1.830.0`
- Start command: image default; pre-deploy: none; healthcheck: none
- Public domain: no; TCP proxy: none; volume: none
- Restart: ALWAYS; replicas: 1; cron: none
- Native mode forces `NUM_WORKERS=8` in-process workers and rejects non-native jobs (native TS, SQL/GraphQL queries and similar).

| Variable | Value | Description |
|---|---|---|
| `MODE` | `worker` | Job worker only. |
| `WORKER_GROUP` | `native` | Worker group for lightweight in-process jobs. |
| `NATIVE_MODE` | `true` | Forces 8 workers per replica, native jobs only (upstream compose). |
| `SLEEP_QUEUE` | `200` | ms between queue polls, multiplied by worker count (upstream compose). |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}?sslmode=disable` | Postgres. |
| `BASE_URL` | `https://${{Proxy.RAILWAY_PUBLIC_DOMAIN}}` | Public URL for generated links. |
| `RUST_LOG` | `info` | Log level. |

### Windmill Extra
- Source: image `ghcr.io/windmill-labs/windmill-extra:1.830.0` (upstream's combined LSP + debugger + multiplayer image with a gateway on port 3000)
- Start command: image entrypoint; pre-deploy: none
- Healthcheck: `/health` on port 3000 (gateway falls through to the LSP health handler), timeout 300 s
- Public domain: no; TCP proxy: none; volume: none (upstream's `lsp_cache` is a cache; an empty Railway volume would also hide what the image keeps in `/pyls/.cache`)
- Restart: ALWAYS; replicas: 1; cron: none
- Holds no database credentials; the debugger verifies backend-signed tokens using the server's `/api/debug/jwks`.

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Gateway port; Railway healthchecks it. The entrypoint sets each sub-service's own port explicitly, so this does not collide. |
| `GATEWAY_PORT` | `3000` | Gateway port. |
| `GATEWAY_HOST` | `::` | Bind the gateway dual-stack (default `0.0.0.0`). |
| `ENABLE_LSP` | `true` | Editor language servers. |
| `ENABLE_DEBUGGER` | `true` | Step-through debugger (upstream default). |
| `ENABLE_MULTIPLAYER` | `false` | Enterprise Edition only. |
| `ENABLE_NSJAIL` | `false` | Needs privileged containers. |
| `REQUIRE_SIGNED_DEBUG_REQUESTS` | `true` | Only accept debug sessions signed by the server. Never `false` on a public deployment. |
| `WINDMILL_BASE_URL` | `http://${{Windmill.RAILWAY_PRIVATE_DOMAIN}}:${{Windmill.PORT}}` | Private server URL for signing keys. |
| `DEBUG_ALLOWED_ORIGINS` | `https://${{Proxy.RAILWAY_PUBLIC_DOMAIN}}` | Browser origins allowed to open debugger websockets; append custom domains (comma-separated). |

### Admin Bootstrap
- Source: repo `baranberkay96/windmill-railway`, root `/services/admin-bootstrap` (Dockerfile `FROM curlimages/curl:8.22.0`, `bootstrap.sh`)
- Start command: image entrypoint (`/bin/sh /bootstrap.sh`); pre-deploy: none; healthcheck: none
- Public domain: no; TCP proxy: none; volume: none
- Restart: **ON_FAILURE, max 10 retries**; replicas: 1; cron: none. It is a one-shot job: it stops after success, which is expected.
- What it does: waits for `/api/version`, logs in as `admin@windmill.dev` with Windmill's documented default password `changeme`, sets the password to `WINDMILL_ADMIN_PASSWORD` via `/api/users/setpassword`, verifies the new password, logs out. If `changeme` is already rejected it exits 0 and changes nothing (idempotent, safe on redeploy). Input is validated (alphanumeric password ≥ 16 chars, plain email, numeric timeout).
- Why: Windmill has no environment variable for the initial superadmin (checked in the v1.830.0 README env table, server help text and self-host docs). Without this job, the public URL accepts `admin@windmill.dev` / `changeme` until someone logs in. `SUPERADMIN_SECRET` was not used: it is a permanent master token, not a password bootstrap.

| Variable | Value | Description |
|---|---|---|
| `WINDMILL_INTERNAL_URL` | `http://${{Windmill.RAILWAY_PRIVATE_DOMAIN}}:${{Windmill.PORT}}` | Private server URL. |
| `WINDMILL_ADMIN_EMAIL` | `admin@windmill.dev` | Seeded superadmin account (Windmill default). |
| `WINDMILL_ADMIN_PASSWORD` | `${{secret(32, "a-zA-Z0-9")}}` (full alphabet in template.json) | Generated first-login password. Change it after first login. |
| `BOOTSTRAP_WAIT_SECONDS` | `900` | How long to wait for the server's first boot. |

### Postgres
- Source: image `ghcr.io/railwayapp-templates/postgres-ssl:18`, copied verbatim from `templates/_railway-base/postgres.json`
- Healthcheck: none (Railway base); public domain: no; TCP proxy: none
- Volume: `/var/lib/postgresql/data`; restart: ON_FAILURE (10); replicas: 1
- Variables: unchanged from the Railway base (`PGDATA`, `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD`, `POSTGRES_DB=railway`, `DATABASE_URL`, `POSTGRES_USER=postgres`, `SSL_CERT_DAYS=820`, `POSTGRES_PASSWORD=${{ secret(32, letters) }}`, `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=60`).
- **Role requirements:** Windmill's migrations create the roles `windmill_user` and `windmill_admin WITH BYPASSRLS` (see upstream `init-db-as-superuser.sql`) and may create extra databases for data tables / DuckLake. `postgres-ssl:18` is built `FROM postgres:18-trixie` and keeps the official entrypoint, so `POSTGRES_USER=postgres` is a superuser and the migrations run unattended. For an external database without superuser rights, run upstream's `init-db-as-superuser.sql` as a privileged role first and grant both roles to the Windmill user (Windmill self-host docs).
- **TLS:** `?sslmode=disable` mirrors upstream `.env` and keeps traffic on Railway's private network. To encrypt it as well, switch all four `DATABASE_URL`s to `sslmode=require` (the image serves a self-signed certificate; `require` encrypts without verifying it).
- **Version:** upstream compose ships `postgres:18`, matching the Railway base.

## Improvements over market templates

1. **Pinned and consistent versions.** All Windmill services on `1.830.0`; `UI371k` mixed `:main` (server) with `:latest` (workers), which allows server/worker version skew on every redeploy.
2. **Current upstream topology.** Deprecated `windmill-lsp:latest` (no numbered tag since `1.603.x`) replaced by `windmill-extra:1.830.0` (LSP + debugger + gateway), exactly as in upstream `docker-compose.yml` at `v1.830.0`.
3. **Private networking only.** `UI371k` routed proxy→server, proxy→LSP and every service→Postgres through public TCP proxies, with `sslmode=disable`, i.e. unencrypted database traffic over the public internet, plus a publicly reachable Postgres. Now: no TCP proxies, `*.railway.internal` everywhere, one public domain.
4. **No hard-coded credentials.** `UI371k` set `POSTGRES_PASSWORD=changeme`; now generated by the Railway base.
5. **Admin bootstrap.** The default `admin@windmill.dev` / `changeme` login is replaced by a generated password automatically. The `windmill` template's `WM_ADMIN_USERNAME`/`WM_ADMIN_PASSWORD=admin` variables have no effect in Windmill.
6. **Healthchecks** on the server (`/api/health/status`, checks the database), on windmill-extra and on the proxy. In the market templates only `UI371k`'s LSP service had one (`/`); no server or proxy was health-checked.
7. **`BASE_URL`** set from the public domain on the server and both worker services (missing in `UI371k`; workers fall back to `http://localhost` without it).
8. **Upstream worker settings.** `MODE=server|worker` instead of `DISABLE_SERVER`/`NUM_WORKERS=0` combinations; native worker with `NATIVE_MODE=true` + `SLEEP_QUEUE=200` (the `UI371k` native worker ran as a single regular worker); 3 default worker replicas and `FAVOR_UNSHARE_PID=true` as in upstream.
9. **Dual-stack binding** (`SERVER_BIND_ADDR=::`, `GATEWAY_HOST=::`) so legacy IPv6-only private networks work.
10. **Proxy rebuilt** on Caddy `2.11.7` (wmprox pinned `2.7.4`), routes `/ws_debug/*` and `/ws_mp/*` as upstream does, has its own healthcheck, and validates its config at build time.
11. **Restart policy ALWAYS** for long-running services, matching upstream `restart: unless-stopped`.
12. **Postgres 18** per upstream compose (market used `latest` or `17`).

## Resource estimate

Estimates from upstream sizing (2 GB limit per worker in compose) and typical footprints of the processes involved; not measured on Railway. Railway bills actual usage.

| Service | Idle RAM | Typical RAM | Typical vCPU | Volume |
|---|---|---|---|---|
| Proxy | 0.03 GB | 0.05 GB | 0.02 | – |
| Windmill (server) | 0.25 GB | 0.5 GB | 0.15 | – |
| Windmill Worker (×3) | 0.18 GB each (0.54) | 0.6 GB each (1.8) | 0.3 each (0.9) | – |
| Windmill Native Worker | 0.15 GB | 0.25 GB | 0.05 | – |
| Windmill Extra | 0.3 GB | 0.7 GB (editor sessions) | 0.1 | – |
| Admin Bootstrap | 0 (exits) | 0 | 0 | – |
| Postgres | 0.12 GB | 0.5 GB | 0.15 | 1 GB idle / 5 GB typical |
| **Total** | **~1.4 GB, ~0.14 vCPU** | **~3.8 GB** | **~1.4 vCPU** | **1–5 GB** |

Monthly cost at RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month:

- **Idle:** 1.4 GB × $10 = $14.00 + 0.14 vCPU × $20 = $2.80 + 1 GB × $0.15 = $0.15 → **≈ $17/month**
- **Typical (small team, steady job load):** 3.8 GB × $10 = $38.00 + 1.37 vCPU × $20 = $27.40 + 5 GB × $0.15 = $0.75 → **≈ $66/month**
- Each extra default worker replica adds roughly $2/month idle and $12/month under steady load.

Minimum plan: **Hobby**. Trial (1 GB RAM per service) can boot the stack for a short evaluation, but heavier Python jobs can exceed 1 GB per worker and the trial credit is consumed quickly. Hobby (up to 48 GB RAM, 5 GB volume per service) covers the default stack; Postgres growth beyond 5 GB or large worker pools need Pro. Job history retention (Instance settings) controls Postgres growth.

## Verification checklist

1. All services deploy; **Admin Bootstrap** logs `Password of admin@windmill.dev rotated` and stops.
2. `https://<proxy-domain>/__proxy/health` → `ok`; `/api/version` → `CE v1.830.0`; `/api/health/status` → `"status":"healthy"` with `workers_alive` > 0.
3. Log in as `admin@windmill.dev` with `WINDMILL_ADMIN_PASSWORD`; confirm `changeme` is rejected. Create a personal superadmin, then change or disable the default account.
4. Workers page: group `default` shows 3 workers, group `native` shows 8.
5. Run a Python script that imports a PyPI package (default worker) and a PostgreSQL or native TypeScript script (native worker).
6. Script editor: Python autocompletion works (browser devtools: `wss://<proxy-domain>/ws/pyright` returns 101). Start a debug session (uses `/ws_debug/`).
7. Schedule a script every minute; confirm runs appear.
8. Trigger a script through its webhook URL with a token.
9. Redeploy Postgres and the server; scripts, runs and users persist.
10. Set Windmill Worker replicas to 4; the Workers page shows 4 default workers.
11. Read worker logs for the unshare warning to know whether per-job PID isolation is active on Railway.

## Open questions

- **Not deployed.** The proxy image and Caddyfile were built and tested locally with stub upstreams (routing, websocket upgrade, healthcheck). The bootstrap script was tested in its container against a mock of the four API calls. Not verified on Railway or against a live Windmill `1.830.0`: `SERVER_BIND_ADDR=::` and `GATEWAY_HOST=::` dual-stack behaviour, healthcheck timing, and `POST /api/users/setpassword` in the Community Edition image (the open-source build stubs it; the published CE image is built with the non-public code and the UI uses the same call). If the bootstrap fails, log in with `changeme` immediately and change the password.
- **Job isolation.** On non-privileged containers PID isolation will probably fall back to "no isolation" and nsjail is unavailable. Jobs run as the same user as the worker and can read the worker's environment, including `DATABASE_URL` with Postgres superuser credentials. Only give script-authoring rights to trusted users. Windmill's own threat model flags this for default installs.
- **Large job logs and service logs.** In CE, Windmill expects a disk shared by server and workers at `/tmp/windmill/logs` (upstream `worker_logs` volume) for older chunks of very large job logs and for the Service logs page; EE can use object storage instead. Railway cannot share volumes, so those views will be incomplete. Recent log output, stored in Postgres, is unaffected.
- **Licence terms (needs legal review before publishing).** The Windmill CE images are distributed under Windmill Labs' own terms: free use and "as is" redistribution, but not to sell, resell, serve as a managed service, modify or wrap without an agreement. This template deploys the unmodified images into the deployer's own Railway account. Whether a revenue-share template counts as "resell"/"managed service" is a legal question; seek professional advice or written confirmation from Windmill Labs.
- `DEBUG_ALLOWED_ORIGINS` must be extended when a custom domain is added, otherwise debugger websockets from that domain are refused.
- Railway's display of a one-shot service that exited 0 (shown as stopped/completed) and whether a 600 s healthcheck timeout is accepted as-is.
- `trusted_proxies static private_ranges` assumes Railway's edge connects from private address space (pattern taken from wmprox). If not, Caddy rewrites `X-Forwarded-Proto` to `http`; Windmill uses `BASE_URL` for its own links, so impact should be limited.
- `windmill-extra` is about 2.2 GB compressed (amd64), so the first deploy of that service is slow; the LSP cache is not persisted.
- Postgres `max_connections` defaults to 100. Server pool default is 50 and each worker replica uses a few connections; beyond roughly 10 default worker replicas, lower the server's `DATABASE_CONNECTIONS` or raise Postgres `max_connections`.
- Windmill releases almost daily; decide a bump cadence (e.g. monthly) and always move all four Windmill images together.
