#!/bin/sh
# Hourly pg_dump backups of the all-agents database with TTL retention.
#
# Runs as PID 1 in the backup sidecar container:
#   * dumps immediately, then every BACKUP_INTERVAL seconds (default 3600)
#   * deletes dumps older than BACKUP_TTL_HOURS (default 48), but never drops
#     below BACKUP_MIN_KEEP dumps (default 3) however old they are
#   * performs a final dump on SIGTERM, so a deliberate
#     `docker compose stop` / `down` loses nothing since the last dump
#   * skips dumping while a restore is in progress (.restoring sentinel) so a
#     half-restored database is never captured
set -eu

: "${BACKUP_DIR:=/backups}"
: "${BACKUP_INTERVAL:=3600}"
: "${BACKUP_TTL_HOURS:=48}"
: "${BACKUP_MIN_KEEP:=3}"
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

    prune
    echo "[backup] done"
}

# TTL retention: drop dumps older than BACKUP_TTL_HOURS, but always keep the
# newest BACKUP_MIN_KEEP dumps so a long pause (laptop asleep, days of downtime)
# can never prune the history down to nothing.
prune() {
    keep=$(ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | head -n "$BACKUP_MIN_KEEP" || true)
    deleted=0
    find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -mmin "+$((BACKUP_TTL_HOURS * 60))" 2>/dev/null | while read -r f; do
        if printf '%s\n' "$keep" | grep -Fqx "$f"; then
            echo "[backup] keeping (within floor of ${BACKUP_MIN_KEEP}) $f"
            continue
        fi
        echo "[backup] pruning (older than ${BACKUP_TTL_HOURS}h) $f"
        rm -f "$f"
    done

    total=$(ls -1 "$BACKUP_DIR"/*.dump 2>/dev/null | wc -l | tr -d ' ')
    echo "[backup] retention: $total dump(s) kept (ttl ${BACKUP_TTL_HOURS}h, floor ${BACKUP_MIN_KEEP})"
    if [ "$total" -lt "$BACKUP_MIN_KEEP" ]; then
        echo "[backup] WARNING: only $total dump(s) present, expected at least $BACKUP_MIN_KEEP"
    fi
}

newest_dump() {
    ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | head -n1 || true
}

# Seconds since the newest dump (999999 when there is none / unreadable).
dump_age() {
    newest=$(newest_dump)
    [ -n "$newest" ] || { echo 999999; return 0; }
    mtime=$(date -r "$newest" +%s 2>/dev/null) || { echo 999999; return 0; }
    case "$mtime" in
        '' | *[!0-9]*) echo 999999; return 0 ;;
    esac
    now=$(date +%s)
    echo $((now - mtime))
}

final_backup() {
    echo "[backup] stopping — final dump before exit"
    [ -n "${sleep_pid:-}" ] && kill "$sleep_pid" 2>/dev/null
    backup_once
    exit 0
}
trap final_backup INT TERM

# Timing is deliberately wall-clock based, because `sleep` counts *monotonic*
# time and that clock stops while the host is suspended. Docker Desktop on a
# laptop therefore turns one long `sleep 3600` into "whenever the machine has
# been awake for a total of an hour" — a single overnight suspend can push the
# next dump out by many real hours. So the loop sleeps in short slices and, on
# every wake (including the first moment after a resume), asks the honest
# question: how old is the newest dump on disk? An empty folder (first boot)
# is treated as a missing dump and triggers the first dump immediately.
TICK=60
[ "$TICK" -le "$BACKUP_INTERVAL" ] || TICK=$BACKUP_INTERVAL
# Dumps are scheduled on absolute wall-clock boundaries: next_due is always the
# next multiple of BACKUP_INTERVAL since the epoch, so an hourly interval dumps
# on the hour and the schedule never drifts later and later. A failed attempt
# simply waits for the next boundary, which paces retries without a hot loop.
now=$(date +%s)
next_due=$(( (now / BACKUP_INTERVAL + 1) * BACKUP_INTERVAL ))

while true; do
    age=$(dump_age)

    # 999999 means no dump on disk at all (first boot) -> that is missing, not
    # merely stale, so it must trigger a dump regardless of the schedule.
    if [ "$age" -ge "$BACKUP_INTERVAL" ] || [ "$age" -eq 999999 ]; then
        # Diagnostically useful: a gap larger than two intervals means the host
        # was suspended or a run was missed, not just a late tick.
        if [ "$age" -ge $((BACKUP_INTERVAL * 2)) ]; then
            echo "[backup] newest dump is ${age}s old (more than 2 x ${BACKUP_INTERVAL}s — host was suspended or a run was missed) — dumping now"
        fi
        backup_once
        # Re-align to the next boundary after a missing/overdue dump, so the
        # cadence returns to the clock instead of inheriting the lateness.
        now=$(date +%s)
        next_due=$(( (now / BACKUP_INTERVAL + 1) * BACKUP_INTERVAL ))
    fi

    # Sleep only until the next boundary, in slices, so a resume is noticed
    # within TICK instead of at the end of a long frozen wait.
    now=$(date +%s)
    left=$(( next_due - now ))
    [ "$left" -ge 1 ] || left=1
    [ "$left" -le "$TICK" ] || left=$TICK
    sleep "$left" &
    sleep_pid=$!
    # `|| true` keeps `set -e` from killing PID 1 if the wait is interrupted
    # (a signal, an unrelated child reaped by the shell, a container event):
    # a dead loop means silently no more backups.
    wait "$sleep_pid" || true

    # Reached a boundary: take the dump and schedule the next boundary.
    if [ "$(date +%s)" -ge "$next_due" ]; then
        backup_once
        next_due=$(( next_due + BACKUP_INTERVAL ))
        # If a boundary was missed entirely (long suspend), skip the backlog
        # instead of dumping repeatedly to catch up on hours nobody needs.
        now=$(date +%s)
        [ "$next_due" -gt "$now" ] || next_due=$(( (now / BACKUP_INTERVAL + 1) * BACKUP_INTERVAL ))
    fi
done
