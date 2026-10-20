# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infra (PostgreSQL + Kafka) as Docker packaging for the all-agents multi-agent
platform (Java Spring Boot app in sibling repo `C:\Work\Projects\AI\all-agents`).
Two stacks, each in its own subdirectory with its own compose file:

- `database/` — PostgreSQL 17 with the platform schema, hourly backups and
  restore-on-start. Schema design follows the database-skills Postgres
  references in `C:\Work\Projects\AI\database-skills\skills\postgres\` — consult
  those before changing schema.
- `kafka/` — single-node KRaft broker for the async processing pipeline:
  `agent-requests` / `agent-events` topics, JSON payload schemas. **The contracts
  (schemas + topic definitions) are kept in both repos** — the mirror lives in
  `all-agents/contracts/kafka/`; change both copies together.
- `k8s-cluster/` — a local Kubernetes cluster for testing Helm charts, shaped
  like the managed service the platform is eventually deployed to. Not a stack:
  there is no compose file. It runs kind inside Docker Desktop, installs the
  services a chart can rely on (storage, usage reporting, ingress under two
  contracts, certificates, secret delivery), and leaves the two stacks above
  running alongside it.
- `database/chart/` — the Helm chart for the database, the Kubernetes
  counterpart of the `database/` stack. It shares that stack's connection
  contract and dump naming, owns no schema, and never generates a credential.

There is no build system, linter, or test suite here; the stacks themselves are
the testbed.

## Commands (database stack, run from `database/`)

```bash
docker compose up -d --build   # start both services (schema applies on first init of an empty volume)
docker compose ps              # healthcheck status; wait for agents-db to be (healthy)
docker compose config --quiet  # validate compose file after edits
docker compose logs agents-db / agents-db-backup
docker exec -i agents-db psql -U agents -d allagents -c '<sql>'   # -i required for stdin
docker compose down            # graceful stop (backup sidecar takes a final dump first)
docker compose down -v         # wipes BOTH volumes: data AND backups — say so before running it
```

## Commands (kafka stack, run from `kafka/`)

```bash
docker compose up -d --build   # build + start the broker; topics created on first start
docker compose ps              # wait for agents-kafka to be (healthy)
docker compose logs agents-kafka
docker exec agents-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
docker compose down / down -v  # down -v wipes the broker volume (topics + messages)
```

Broker listens on `localhost:9092` (env knobs: `KAFKA_PORT`, `KAFKA_ADVERTISED_HOST`).
The wrapper entrypoint starts the broker, waits for a real API handshake, creates
the topics from `topics/topics.txt` (idempotent), then keeps running as the broker.

Git Bash on Windows mangles container-internal absolute paths (`/backups` → `C:/Program Files/Git/backups`); prefix such commands with `MSYS_NO_PATHCONV=1`.

## Commands (local cluster, run from `k8s-cluster/`)

```bash
sh scripts/up.sh                      # create the cluster for a profile (idempotent)
sh scripts/vault-seed.sh              # seed this profile's credentials, mint the cluster token
sh scripts/addons-up.sh               # install or upgrade the platform services
sh scripts/smoke-test.sh              # the whole acceptance bar, one line per check
sh scripts/status.sh                  # what exists, which nodes, which version
sh scripts/down.sh                    # remove the cluster (idempotent)
sh scripts/up.sh local --render-only  # print the kind configuration a profile produces
```

Seeding comes before the addons on purpose: the addon that delivers secrets refuses to run without the token the seed step mints.

The chart is installed and driven from its own directory: `sh database/chart/install.sh local`, plus `fetch-dump.sh`, `restore.sh` and `init-schema.sh` beside it.

Nothing here is installed with administrator rights except `choco upgrade kind` and `choco upgrade kubernetes-cli`, which the developer runs from an elevated shell because Chocolatey requires it.

Env knobs (compose, defaults in docker-compose.yml): `POSTGRES_PORT` (5432), `POSTGRES_DB` (allagents), `POSTGRES_USER/PASSWORD` (agents), `BACKUP_INTERVAL` (3600), `BACKUP_KEEP` (24), `RESTORE_ON_START` (true). No `.env` file exists; defaults are inline.

> **Known stale, deliberately left alone.** The `BACKUP_KEEP` name above, and the `pgbackups` named volume described further down, predate the switch to TTL retention (`BACKUP_TTL_HOURS`, `BACKUP_MIN_KEEP`) and the `./bck` bind mount. The working tree is authoritative. This was recorded rather than corrected during the Kubernetes work, because rewriting the container stack's documentation was outside that work's scope.

## Architecture: the lifecycle that spans five files

`schema.sql`, `Dockerfile`, `docker-compose.yml`, and `scripts/*.sh` together implement a specific start/backup/restore contract — change one part, re-check the others:

- **First boot only**: `schema.sql` runs via `/docker-entrypoint-initdb.d` on the official image, i.e. only when `pgdata` is empty. Editing it has no effect on an existing volume — `down -v && up` re-applies it.
- **Every start**: `docker-entrypoint-wrapper.sh` replaces the official entrypoint (compose `entrypoint:` + `command: ["postgres"]`). It backgrounds the official entrypoint, waits for the server on TCP `127.0.0.1:5432` (the temp init server is unix-socket-only, so TCP-ready means init scripts finished), then runs `restore.sh`.
- **Restore semantics**: `restore.sh` drops and recreates the database, then `pg_restore`-s the newest dump from the shared `pgbackups` volume. So any container start rolls the DB back to the last hourly dump — a forced/crash restart loses changes since then, by design. A graceful `stop`/`down` loses nothing: the `backup` sidecar traps SIGTERM and dumps before exiting (compose stops it first via reverse dependency order). No backup yet → restore skips, fresh schema stands.
- **Backup sidecar**: same image, `entrypoint: backup.sh`. `pg_dump -Fc` immediately and every `BACKUP_INTERVAL` seconds, prune to newest `BACKUP_KEEP`, skip while `/backups/.restoring` sentinel exists so a half-restored DB is never captured.
- **Shared volume**: both containers mount `pgbackups` at `/backups`; postgres reads it, backup writes it.

## Schema conventions (schema.sql)

- Follows schema-design.md: `BIGINT GENERATED ALWAYS AS IDENTITY` surrogates, `TIMESTAMPTZ` only, CHECK constraints instead of ENUMs (lowercase values matching the app's Java enums), every FK column indexed, `{table}_{column}_idx/_check/_fkey` naming, singular snake_case, `created_at DEFAULT now()` everywhere, BRIN on the append-only `agent_event`.
- Deliberate deviation: `conversation.id`, `task.id` etc. are `UUID` PKs because the app generates those IDs and queries by them; do not "fix" them to BIGINT without adapting the app.
- Presets are seeded from `all-agents/app/src/main/resources/application.yml`; keep the seed in sync if that file changes.
- App adapter notes (README has details): PgJDBC does not cast `varchar`→`uuid`, and the app's H2-flavored `schema.sql` (CLOB/AUTO_INCREMENT) must be replaced, not reused.

## Validation workflow

The proven way to verify lifecycle changes (used to validate this repo end-to-end):

```bash
# short intervals on a non-default port, so the real stack is untouched
POSTGRES_PORT=5433 BACKUP_INTERVAL=5 BACKUP_KEEP=3 docker compose up -d --build
# then: insert row → wait one interval (it gets dumped) → insert another row →
# docker compose restart postgres → first row survives, second is rolled back
# then: insert row → docker compose stop → up → row survived via final-dump-on-stop
docker compose down -v   # always clean up the test run
```

## Script gotchas

- Alpine = busybox `ash`: use `: "${VAR:=default}"` (`:=`, not `:-`) to assign defaults, and `trap 'fn' INT TERM` + `sleep N & wait $!` so traps interrupt sleep.
- The wrapper must forward `INT`/`TERM` to the backgrounded server PID or `docker stop` kills postgres uncleanly.
- **Docker Desktop on Windows host + directory `COPY`**: directory COPYs from the Windows host lose the execute bit (dirs land as `drw-r--r--`) and any `RUN chmod` afterwards fails with "Operation not permitted". Use `COPY --chmod=...` instead — `--chmod=go+rwX` for contract dirs (the apache/kafka image runs as non-root `appuser`, files must be world-readable), `--chmod=755` for scripts. Never remove the `--chmod` flags.
- Git Bash mangles container-internal absolute paths in `docker exec` commands (`/opt/...` → `C:/Program Files/Git/opt/...`); prefix such commands with `MSYS_NO_PATHCONV=1`.
