#!/bin/sh
# Wrapper around the official postgres entrypoint:
#   1. starts the server (first boot runs schema.sql via /docker-entrypoint-initdb.d)
#   2. waits until it accepts TCP connections (the temp init server is unix-socket
#      only, so a TCP success means init scripts have finished)
#   3. restores the latest backup, unless RESTORE_ON_START=false
#   4. stays attached so `docker stop` shuts the server down gracefully
set -eu

/usr/local/bin/docker-entrypoint.sh "$@" &
SERVER_PID=$!

trap 'kill -TERM "$SERVER_PID"' INT TERM

echo "[entrypoint] waiting for PostgreSQL to accept connections..."
until pg_isready -h 127.0.0.1 -p 5432 -U "$POSTGRES_USER" -d postgres -q 2>/dev/null; do
    sleep 1
done
echo "[entrypoint] PostgreSQL is up"

if [ "${RESTORE_ON_START:-true}" = "true" ]; then
    /usr/local/bin/restore.sh || echo "[entrypoint] restore failed — continuing with the current database state"
fi

wait "$SERVER_PID"
