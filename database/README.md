# agents-database

PostgreSQL schema for the [all-agents](file:///C:/Work/Projects/AI/all-agents) multi-agent platform, plus a Dockerfile and docker-compose to run it in Docker Desktop, with hourly backups into the host folder `bck/` (TTL retention, at least 3 dumps kept) and automatic restore on every container start.

## Run

```bash
docker compose up -d --build
```

The schema (`schema.sql`) is applied automatically by the official Postgres image on the first start of an empty volume. Wait for the healthcheck to turn `healthy` (`docker compose ps`).

## Connect

| Setting  | Value                                        |
|----------|----------------------------------------------|
| Host     | `localhost`                                  |
| Port     | `${POSTGRES_PORT:-5432}`                     |
| Database | `${POSTGRES_DB:-allagents}`                  |
| User     | `${POSTGRES_USER:-agents}`                   |
| Password | `${POSTGRES_PASSWORD:-agents}`               |
| JDBC URL | `jdbc:postgresql://localhost:5432/allagents` |

Override any value by exporting the variable or placing it in a local `.env` file. The default password is for local development only.

Quick check inside the container:

```bash
docker exec agents-db psql -U agents -d allagents -c '\dt'
```

## Backup & restore

A `backup` sidecar container runs next to Postgres:

- **Every hour** it takes a `pg_dump --format=custom` dump of the database into `./bck` on the host (bind-mounted at `/backups` inside both containers), so the dumps are plain files you can see, copy and inspect with Explorer.
- **Retention is TTL-based**: dumps older than `BACKUP_TTL_HOURS` (default 48) are deleted, but the newest `BACKUP_MIN_KEEP` dumps (default 3) are always kept even if they are older than the TTL, so a long pause can never prune the history down to nothing.
- **On every Postgres container start**, the entrypoint wrapper restores the latest dump: the database is dropped, recreated, and loaded with `pg_restore`. This runs on any start — `docker compose up`, `docker compose restart postgres`, or Docker Desktop auto-starting the container after a VM reboot.
- **On graceful stop** (`docker compose stop` / `down`, machine shutdown), the backup container takes a final dump first — so a deliberate restart loses nothing; the restore on the next start picks up exactly where you left off.
- Restore is skipped while no backup exists yet (first boot keeps the freshly initialized schema), and dumps are skipped while a restore is in flight so a half-restored database is never captured.

Timing never trusts `sleep` alone. On a laptop this matters more than it sounds: while Windows is suspended (Modern Standby), the container's *monotonic* clock freezes, so a single `sleep 3600` can take many real hours to return — an overnight suspend was measured turning a 60-second wait into 9h44m. A loop built on one long sleep therefore stops dumping for as long as the machine is suspended, and resumes far too late. Instead the loop sleeps in 60-second slices and, on every wake, asks the honest question: how old is the newest dump on disk?

- Dumps are scheduled on absolute wall-clock boundaries: the next dump is always the next multiple of `BACKUP_INTERVAL` seconds since the epoch, so an hourly interval dumps on the hour and the schedule never drifts later and later. Measured after a resume, the catch-up dump appeared **8 seconds** and **49 seconds** after wake (both inside a single 60s slice) — against hours under the old long-sleep loop.
- A dump also happens immediately on first boot, or whenever the newest dump on disk is already older than `BACKUP_INTERVAL` when the loop starts (for example right after a `docker compose stop`/`start` on a folder whose newest dump is stale).
- A missed boundary is skipped rather than backfilled: one catch-up dump after a long suspend, not one per suspended hour.
- A failed dump (database down, still restoring) is retried by simply waiting for the next boundary, so the scheduler can never hot-loop against a database that is unavailable.
- A log line reading `newest dump is Ns old (more than 2 x 3600s ...)` is a diagnostic that a suspend or a missed run happened — not an error, and not a precondition for dumping.

Worst-case gap is one interval plus the time the machine spent suspended, and it is always bounded — the folder can never silently stop receiving dumps.

| Variable | Default | Meaning |
| --- | --- | --- |
| `BACKUP_INTERVAL` | `3600` | Seconds between dumps |
| `BACKUP_TTL_HOURS` | `48` | Delete dumps older than this (hours) |
| `BACKUP_MIN_KEEP` | `3` | Always keep at least this many dumps, however old |
| `RESTORE_ON_START` | `true` | Set `false` to disable automatic restore on start |

Trade-off to be aware of: restore-on-start always rolls the database back to the latest dump, so an unexpected restart (container crash, forced restart) discards changes made since the last hourly dump. For a deliberate `stop`/`down` nothing is lost (final dump on stop).

The dumps are already on the host — no `docker cp` needed:

```powershell
Get-ChildItem C:\Work\Projects\AI\agents-infra\database\bck   # newest first: Sort-Object Name -Descending
```

To restore one manually into a running stack:

```bash
docker exec -i agents-db pg_restore --clean --if-exists -U agents -d allagents < dumpfile.dump
```

## Stop / reset

```bash
docker compose down        # stop, keep data and backups (bck/ files are untouched)
docker compose down -v     # stop and wipe the DATA volume (bck/ dumps survive — they are plain files)
```

The old named volume `agents-database_pgbackups` from before the switch to `./bck` is no longer mounted and can be deleted once you no longer need it:

```bash
docker volume rm agents-database_pgbackups
```

To reset only the database but keep backups, remove just the data volume:

```bash
docker volume rm agents-database_pgdata
```

## Schema overview

| Table              | Purpose                                                        |
| ------------------ | -------------------------------------------------------------- |
| `preset`           | Chat presets, seeded from the app's `application.yml`          |
| `agent`            | Agent registry/catalog (A2A agent card + lifecycle status)     |
| `agent_capability` | Capabilities advertised by an agent                            |
| `agent_skill`      | Skills advertised by an agent (with examples)                  |
| `tool`             | Tool catalog searched by the master agent                      |
| `agent_tool`       | Tools available to an agent                                    |
| `conversation`     | Chat conversations (UUID ids generated by the app)             |
| `message`          | Conversation history shown in the UI                           |
| `chat_memory`      | Spring AI `ChatMemory` store (recent history sent to the LLM)  |
| `task`             | A2A protocol tasks and their state transitions                 |
| `agent_request`    | Delegation requests (instruction + payload + correlation id)   |
| `agent_result`     | Results of delegation requests                                 |
| `agent_event`      | Append-only event log (started/stopped/completed/failed)       |
| `guardrail_check`  | Audit log of guardrail decisions (allowed/blocked/redacted)    |

## Design notes

- Best practices from the database-skills Postgres references: `BIGINT GENERATED ALWAYS AS IDENTITY` surrogate keys, `TIMESTAMPTZ`, CHECK constraints instead of ENUMs, all FK columns indexed, explicit `ON DELETE` behavior, singular snake_case naming, `created_at` on every table, BRIN index on the append-only event log.
- `conversation.id`, `task.id` and message ids remain `UUID` primary keys because the app generates them and queries by that exact value — a surrogate BIGINT would only add joins.

## Pointing the all-agents app at this database

The app currently uses embedded H2. To switch (adapter work required):

1. Add the PostgreSQL driver dependency (`org.postgresql:postgresql`) to `app/pom.xml`.
2. Set in `application.yml`:
   ```yaml
   spring:
     datasource:
       url: jdbc:postgresql://localhost:5432/allagents
       driver-class-name: org.postgresql.Driver
       username: agents
       password: ${POSTGRES_PASSWORD:agents}
   ```
3. Replace the H2-flavored `schema.sql` with this one (H2 `CLOB`/`AUTO_INCREMENT` are not valid Postgres).
4. When writing UUID columns through `JdbcTemplate`, pass `UUID.fromString(id)` (via `setObject`) rather than a plain `String` — PgJDBC does not cast `varchar` to `uuid` implicitly.
