#!/bin/sh
# Restore one dump into the database. Run deliberately, never on start.
#
# The container stack restores the newest dump every time its container starts.
# That is not carried over: in a cluster it would let a readiness probe report
# the database as available while a restore was still overwriting writes, and a
# restart would silently discard everything written since the last dump. Here a
# restore happens because someone asked for one, and says which dump.
#
# The sentinel is the same file the container stack uses, so a dump job running
# anywhere in this repository knows to stay away while a restore is in flight.
set -eu

: "${BACKUP_DIR:=/backups}"
: "${PGHOST:=agents-db}"
: "${RESTORE_FILE:?RESTORE_FILE must name a dump present in $BACKUP_DIR}"

export PGPASSWORD="$POSTGRES_PASSWORD"

DUMP="$BACKUP_DIR/$RESTORE_FILE"
if [ ! -f "$DUMP" ]; then
	echo "[restore] no such dump: $DUMP" >&2
	echo "[restore] available:" >&2
	ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | sed 's|.*/|  |' >&2 || true
	exit 1
fi

echo "[restore] restoring $(basename "$DUMP") into $POSTGRES_DB"

# Cleared before it is taken, not merely taken. A sentinel left behind by a
# process running as a different user cannot be written to, and removing it is
# permitted by the directory alone, so removing first is what makes a
# previously abandoned restore recoverable instead of a permanent blocker.
rm -f "$BACKUP_DIR/.restoring"
if ! touch "$BACKUP_DIR/.restoring" 2>/dev/null; then
	echo "[restore] cannot write the sentinel in $BACKUP_DIR, so dumps could capture a half-restored database; refusing to start" >&2
	exit 1
fi
# The sentinel is removed however this exits, so one failed restore does not
# leave dumps switched off behind it.
trap 'rm -f "$BACKUP_DIR/.restoring"' EXIT INT TERM

# Disconnect anything still attached, then drop and recreate, so the result is
# the dump's state rather than a merge with whatever was there.
#
# ON_ERROR_STOP is not optional here. Without it psql exits successfully even
# when the drop or the create failed, and a failed create turns the following
# restore into a merge with the existing database rather than a replacement:
# the restore reports success and the old rows are still there.
echo "[restore] dropping and recreating $POSTGRES_DB"
psql -v ON_ERROR_STOP=1 -h "$PGHOST" -U "$POSTGRES_USER" -d postgres -q \
	-c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();" \
	-c "DROP DATABASE IF EXISTS $POSTGRES_DB;" \
	-c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

echo "[restore] loading the dump"
pg_restore --no-owner --exit-on-error -h "$PGHOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$DUMP"

echo "[restore] done"
