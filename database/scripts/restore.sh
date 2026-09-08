#!/bin/sh
# Restore the latest backup into the database on container start.
#
# For an exact restore of the backup state, the database is dropped and
# recreated, then loaded with pg_restore (custom-format dump from backup.sh).
# While a restore runs, a .restoring sentinel tells the backup sidecar to
# skip its next dump so a half-restored database is never captured.
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
export PGPASSWORD="$POSTGRES_PASSWORD"

LATEST=$(ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | head -n1 || true)
if [ -z "$LATEST" ]; then
    echo "[restore] no backup found in $BACKUP_DIR — keeping the freshly initialized database"
    exit 0
fi

echo "[restore] restoring latest backup: $(basename "$LATEST")"
touch "$BACKUP_DIR/.restoring"

# disconnect anything still attached, then drop + recreate the database
psql -h 127.0.0.1 -U "$POSTGRES_USER" -d postgres -q \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();" \
    -c "DROP DATABASE IF EXISTS $POSTGRES_DB;" \
    -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

pg_restore --no-owner -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$LATEST"

rm -f "$BACKUP_DIR/.restoring"
echo "[restore] done"
