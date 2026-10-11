# Deploy and Host Windmill with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/windmill-v1-scripts-flows-and-internal-a?referralCode=20H68q)

Windmill is an open-source developer platform that turns Python, TypeScript, Go, Bash and SQL scripts into flows, auto-generated UIs, internal apps, webhooks and cron jobs. This community template runs the full self-hosted stack on Railway: API server, scalable worker pool, native worker, editor services and Postgres.

## About Hosting Windmill

A production Windmill install is more than one container. The server serves the UI and REST API and runs database migrations; workers pull jobs from a queue stored in Postgres and execute your code; a native worker handles lightweight queries and HTTP calls in-process; the windmill-extra service provides editor autocompletion and a step-through debugger over websockets. Because Railway gives each service a single public port, a small Caddy proxy sends editor websocket paths to windmill-extra and everything else to the server. Everything except the proxy stays on Railway's private network, all images are pinned to the same Windmill release, and the default admin password is replaced automatically on first boot.

## Common Use Cases

- Turn one-off Python or TypeScript scripts into shareable tools with generated input forms
- Run scheduled jobs and data syncs (ETL, reports, clean-ups) with retries and run history
- Chain scripts into multi-step flows with branches, approvals and error handlers
- Build internal apps and dashboards on top of existing databases and APIs
- Expose scripts as authenticated webhooks for other systems to call

## Dependencies for Windmill Hosting

- Windmill server and workers (`ghcr.io/windmill-labs/windmill:1.830.0`)
- Windmill Extra for the editor's language servers and debugger (`ghcr.io/windmill-labs/windmill-extra:1.830.0`)
- PostgreSQL 18 (Railway's `postgres-ssl:18`), which also holds Windmill's job queue
- Caddy 2.11 as the public path-routing proxy
- A one-shot bootstrap job (curl) that replaces the default admin password

### Deployment Dependencies

- Windmill source and releases: https://github.com/windmill-labs/windmill
- Windmill self-hosting guide: https://www.windmill.dev/docs/advanced/self_host
- Windmill workers and worker groups: https://www.windmill.dev/docs/core_concepts/worker_groups
- Windmill job isolation options: https://www.windmill.dev/docs/advanced/security_isolation
- Caddy reverse_proxy: https://caddyserver.com/docs/caddyfile/directives/reverse_proxy
- Railway private networking: https://docs.railway.com/networking/private-networking

### Implementation Details

| Service | Role | Public | Scaling |
|---|---|---|---|
| Proxy | Caddy; routes `/ws/*`, `/ws_debug/*`, `/ws_mp/*` to Windmill Extra, everything else to Windmill | Yes (only public service) | 1 |
| Windmill | API server and UI (`MODE=server`), runs migrations on start | No | 1 |
| Windmill Worker | Default worker group: Python, TypeScript, Bash, Go and other jobs | No | 3 replicas (adjustable) |
| Windmill Native Worker | `native` worker group, 8 in-process workers for queries and HTTP calls | No | 1 |
| Windmill Extra | Language servers and debugger behind one gateway | No | 1 |
| Admin Bootstrap | One-shot job that replaces the default admin password, then stops | No | – |
| Postgres | Database and job queue, persistent volume | No | 1 |

**First login**

1. Wait until all services are deployed and the Admin Bootstrap logs show `Password of admin@windmill.dev rotated`. The job stopping afterwards is expected.
2. Copy `WINDMILL_ADMIN_PASSWORD` from the Admin Bootstrap service's Variables tab.
3. Open the Proxy service's public URL and sign in as `admin@windmill.dev` with that password.
4. In Instance settings, confirm the Base URL, then add your own user as superadmin, sign in with it, and change or disable `admin@windmill.dev`.
5. If the bootstrap job failed for any reason, sign in immediately with Windmill's default password `changeme` and change it, because the URL is public.

**Scaling workers**

Each default worker replica runs one job at a time. Raise or lower the Windmill Worker replica count in its service settings; new replicas register themselves on Windmill's Workers page. Workers keep their dependency cache on local disk, so the first run of a script with new packages after a redeploy or on a new replica downloads them again. Do not attach a volume at `/tmp/windmill/cache`: replicas cannot use volumes, and an empty volume would hide runtimes the image pre-installs there. Postgres allows 100 connections by default; past about 10 worker replicas, lower the server's `DATABASE_CONNECTIONS` or raise Postgres `max_connections`.

**Pinning and upgrading**

Windmill, Windmill Worker, Windmill Native Worker and Windmill Extra all use release `1.830.0`. To upgrade, back up the Postgres volume, then set the same new tag (see https://github.com/windmill-labs/windmill/releases) on all four services and deploy; the server applies database migrations on start. Database migrations are not designed to be rolled back, so test upgrades in a separate Railway environment first.

**Limits on Railway**

Railway does not offer privileged containers, so nsjail sandboxing is unavailable and per-job PID isolation may fall back to none (check worker logs). Treat everyone who can write scripts as trusted. Enterprise-only parts of the upstream stack (search indexer, multiplayer) and the Docker-in-Docker and SMTP email-trigger options are not included.

### Why Deploy Windmill on Railway?

Railway runs each Windmill component as its own service with private networking, managed Postgres with a persistent volume, and per-service logs and metrics, so the worker pool can grow by changing a replica count instead of editing compose files on a server. You pay for the resources the stack actually uses, and every image tag is pinned so upgrades happen when you choose.
