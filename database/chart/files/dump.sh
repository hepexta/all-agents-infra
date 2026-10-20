#!/bin/sh
# One dump, then prune. The scheduled counterpart of the backup loop that runs
# in the container stack, sharing its naming, its retention rules and its
# sentinel, so that a dump taken here and a dump taken there are the same
# artefact and can be restored by either.
#
# Differences from the loop, and why: this runs once per scheduled job rather
# than forever, so the wall-clock pacing and the suspend handling stay in the
# loop, and the schedule itself is the cluster's job. The database is reached
# over the network by service name rather than over a local socket.
set -eu

: "${BACKUP_DIR:=/backups}"
: "${BACKUP_TTL_HOURS:=48}"
: "${BACKUP_MIN_KEEP:=3}"
: "${STALE_SENTINEL_MINUTES:=120}"
: "${PGHOST:=agents-db}"

export PGPASSWORD="$POSTGRES_PASSWORD"
mkdir -p "$BACKUP_DIR"

# A restore in progress leaves a sentinel so that a half-restored database is
# never captured. A sentinel left behind by a restore that died must not stop
# dumps for ever, so an old one is ignored rather than obeyed.
if [ -f "$BACKUP_DIR/.restoring" ]; then
	if [ -n "$(find "$BACKUP_DIR" -maxdepth 1 -name .restoring -mmin "-$STALE_SENTINEL_MINUTES" 2>/dev/null)" ]; then
		echo "[dump] a restore is in progress, skipping this run"
		exit 0
	fi
	echo "[dump] ignoring a stale restore sentinel older than $STALE_SENTINEL_MINUTES minutes"
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
file="$BACKUP_DIR/allagents-$stamp.dump"
tmp="$file.tmp"

echo "[dump] dumping $POSTGRES_DB from $PGHOST as $POSTGRES_USER -> $(basename "$file")"
if ! pg_dump --format=custom -h "$PGHOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$tmp"; then
	echo "[dump] failed, the next scheduled run will try again"
	rm -f "$tmp"
	exit 1
fi
mv "$tmp" "$file"

# TTL retention with a floor: drop dumps older than the window, but always keep
# the newest few however old they are, so a long pause cannot prune the history
# down to nothing.
keep=$(ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | head -n "$BACKUP_MIN_KEEP" || true)
find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -mmin "+$((BACKUP_TTL_HOURS * 60))" 2>/dev/null | while read -r f; do
	if printf '%s\n' "$keep" | grep -Fqx "$f"; then
		echo "[dump] keeping $(basename "$f"), within the floor of $BACKUP_MIN_KEEP"
		continue
	fi
	echo "[dump] pruning $(basename "$f"), older than ${BACKUP_TTL_HOURS}h"
	rm -f "$f"
done

total=$(ls -1 "$BACKUP_DIR"/*.dump 2>/dev/null | wc -l | tr -d ' ')
echo "[dump] retention: $total dump(s) present (ttl ${BACKUP_TTL_HOURS}h, floor ${BACKUP_MIN_KEEP})"
[ "$total" -ge "$BACKUP_MIN_KEEP" ] || echo "[dump] WARNING: only $total dump(s) present"
echo "[dump] done"
