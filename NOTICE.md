# Notice

## Upstream software

- **Windmill** by Windmill Labs, Inc. Source code is licensed per file under AGPLv3 or Apache-2.0, with proprietary code for Enterprise features (see the repository `LICENSE`). The Community Edition images used here (`ghcr.io/windmill-labs/windmill`, `ghcr.io/windmill-labs/windmill-extra`) also contain non-public code and are distributed by Windmill Labs under their own Community Edition terms stated in that `LICENSE` file (free use and redistribution as is; selling, reselling, offering as a managed service, modifying or wrapping require an agreement with Windmill Labs). This template deploys the unmodified images.
  - `ghcr.io/windmill-labs/windmill:1.830.0` — publisher: Windmill Labs (server, default worker, native worker)
  - `ghcr.io/windmill-labs/windmill-extra:1.830.0` — publisher: Windmill Labs (LSP, debugger, gateway)
- **Caddy** — Apache-2.0, Caddy project / Matthew Holt and contributors. Image `caddy:2.11.7-alpine` (Docker Official Image), used as the base of `services/proxy`.
- **curl** — curl license (MIT-style), Daniel Stenberg and contributors. Image `curlimages/curl:8.22.0` (curl project's container image, repository `curl/curl-container`, MIT), used as the base of `services/admin-bootstrap`.
- **PostgreSQL** — PostgreSQL License. Image `ghcr.io/railwayapp-templates/postgres-ssl:18` — publisher: Railway (repository `railwayapp-templates/postgres-ssl`, MIT), built on the official `postgres:18` image.

## Verified against

All checked on 2026-10-10. Windmill files at git tag `v1.830.0`, commit `0a19d26d5f9623b805a7a4cd2e3fc44255a6efee` (https://github.com/windmill-labs/windmill/tree/v1.830.0):

| What | Upstream file / source |
|---|---|
| Service topology, worker env, replicas, Postgres 18, windmill-extra env, omitted indexer/reports/DinD | `docker-compose.yml` |
| `DATABASE_URL` format with `sslmode=disable`, image naming | `.env` |
| Path routing `/ws/*`, `/ws_mp/*`, `/ws_debug/*` → windmill-extra:3000, rest → server:8000 | `Caddyfile` |
| windmill-extra ports, `ENABLE_*` flags, gateway, `HOST`/ports per sub-service | `docker/DockerfileExtra`, `docker/entrypoint-extra.sh`, `multiplayer/gateway.mjs` |
| LSP `/health` handler and bind address | `lsp/pyls_launcher.py` |
| Debugger signing (`REQUIRE_SIGNED_DEBUG_REQUESTS`, `WINDMILL_BASE_URL`, `DEBUG_ALLOWED_ORIGINS`), `windmill prepare-deps` use | `debugger/dap_debug_service.ts` |
| `MODE`, `PORT`, `SERVER_BIND_ADDR` (defaults 0.0.0.0 server / 127.0.0.1 worker), `NUM_WORKERS` forced to 1 outside native mode, `NATIVE_MODE` forcing 8, env help text | `backend/src/main.rs` |
| `BASE_URL` env fallback (`http://localhost`) and instance-setting override | `backend/src/monitor.rs` |
| Pool sizes / `DATABASE_CONNECTIONS` | `backend/src/db_connect.rs` |
| `/api/health/status` (unauthenticated; 503 only when DB unhealthy), `/api/version` | `backend/windmill-api/src/health.rs`, `backend/windmill-api/src/lib.rs` |
| `POST /api/auth/login`, `POST /api/users/setpassword`, `POST /api/auth/logout` | `backend/windmill-api/openapi.yaml`, `backend/windmill-api/src/users.rs`, `backend/windmill-api-users/src/users.rs`, `frontend/src/lib/components/settings/UserInfoSettings.svelte` |
| Default admin `admin@windmill.dev` / `changeme`, env var table incl. `SUPERADMIN_SECRET`, `NATIVE_MODE`, `SLEEP_QUEUE` | `README.md` |
| `FAVOR_UNSHARE_PID` fallback to no isolation, nsjail off by default | `backend/windmill-worker/src/worker.rs`, `backend/THREAT_MODEL.md` |
| Shared `/tmp/windmill/logs` disk expectation in CE | `frontend/src/lib/components/LogViewer.svelte` |
| Runtimes pre-installed under `/tmp/windmill/cache` | `Dockerfile` |
| Roles `windmill_user`, `windmill_admin WITH BYPASSRLS` | `init-db-as-superuser.sql` |
| Licensing | `LICENSE`, `NOTICE` |

Other sources:

- Release list and latest release `v1.830.0` (2026-10-09): `gh api repos/windmill-labs/windmill/releases/latest`.
- Image tags `windmill:1.830.0`, `windmill-extra:1.830.0` exist; `windmill-lsp` has no numbered tag after `1.603.x`: GHCR registry API.
- `caddy:2.11.7-alpine` (Docker Hub tag list; Caddy release v2.11.7 on 2026-10-03), `curlimages/curl:8.22.0` (Docker Hub tag list).
- Windmill docs: https://www.windmill.dev/docs/advanced/self_host (first login, Postgres without superuser, Postgres 18), https://www.windmill.dev/docs/advanced/security_isolation, https://www.windmill.dev/docs/core_concepts/service_logs.
- `railwayapp-templates/postgres-ssl` `Dockerfile.18` (`FROM postgres:${POSTGRES_VERSION}-${DEBIAN_RELEASE}`, official entrypoint kept) and `wrapper.sh`, main branch.

## Adapted code

- **rconjoe/wmprox** — `Caddyfile`. Copyright (c) 2023 Railway. MIT License. Adapted into `services/proxy/Caddyfile`: the global-options pattern for running Caddy behind Railway (`admin off`, `persist_config off`, `auto_https off`, `trusted_proxies static private_ranges`, `:{$PORT}` site address, upstreams from environment variables). Changed: rewritten routing (named matcher for `/ws/*`, `/ws_debug/*`, `/ws_mp/*` to windmill-extra, `handle` blocks), private-network upstream defaults, local healthcheck route, comments. The Dockerfile was rewritten (Caddy 2.11.7, build-time `caddy validate`).

```
MIT License

Copyright (c) 2023 Railway

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- `services/admin-bootstrap/bootstrap.sh` and its Dockerfile are original to this template; they only call Windmill's documented REST API.
- Windmill's own `Caddyfile` (AGPLv3 repository) was read to match its routing behaviour; no text from it was copied.

## Reference only (not copied)

- `Pluma-Negra/windmill-railway` (`_upstream/Pluma-Negra__windmill-railway`): no license. Read for ideas only; no files or text copied.
- Railway marketplace templates `UI371k`, `windmill`, `windmill-1` (`_market/*.json`): configuration reviewed for comparison; no README text copied.

## Trademarks

The Windmill name and logo belong to Windmill Labs, Inc. Caddy, curl, PostgreSQL and Railway names belong to their respective owners. This is a community template; it is not affiliated with, endorsed by or supported by Windmill Labs, Inc.
