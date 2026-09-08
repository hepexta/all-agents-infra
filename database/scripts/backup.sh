#!/bin/sh
# Hourly pg_dump backups of the all-agents database with retention pruning.
#
# Runs as PID 1 in the backup sidecar container:
#   * dumps immediately, then every BACKUP_INTERVAL seconds (default 3600)
#   * keeps the newest BACKUP_KEEP dumps (default 24 = one day of hourly dumps)
#   * performs a final dump on SIGTERM, so a deliberate
#     `docker compose stop` / `down` loses nothing since the last dump
#   * skips dumping while a restore is in progress (.restoring sentinel) so a
#     half-restored database is never captured
set -eu

: "${BACKUP_DIR:=/backups}"
: "${BACKUP_INTERVAL:=3600}"
: "${BACKUP_KEEP:=24}"
: "${PGHOST:=postgres}"

export PGPASSWORD="$POSTGRES_PASSWORD"
mkdir -p "$BACKUP_DIR"

backup_once() {
    if [ -f "$BACKUP_DIR/.restoring" ]; then
        echo "[backup] restore in progress — skipping this run"
        return 0
    fi

    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    file="$BACKUP_DIR/allagents-$stamp.dump"
    tmp="$file.tmp"

    echo "[backup] dumping $POSTGRES_DB -> $(basename "$file")"
    if ! pg_dump --format=custom -h "$PGHOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$tmp"; then
        echo "[backup] dump failed (database not ready?) — will retry on the next interval"
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$file"

    # retention: keep the newest $BACKUP_KEEP dumps, prune the rest
    ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) | while read -r old; do
        echo "[backup] pruning $old"
        rm -f "$old"
    done

    echo "[backup] done"
}

final_backup() {
    echo "[backup] stopping — final dump before exit"
    backup_once
    exit 0
}
trap final_backup INT TERM

backup_once
while true; do
    sleep "$BACKUP_INTERVAL" &
    wait $!
    backup_once
done
