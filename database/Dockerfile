# all-agents database: PostgreSQL with the schema applied on first boot,
# hourly backups (scripts/backup.sh) and restore-on-start (scripts/restore.sh).
#
# The official image executes every *.sql file in /docker-entrypoint-initdb.d
# the first time an empty data volume is mounted, so schema.sql only runs once.
# pg_dump / pg_restore / psql ship with the base image.
FROM postgres:17-alpine

COPY schema.sql /docker-entrypoint-initdb.d/001_schema.sql

COPY scripts/docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
COPY scripts/restore.sh /usr/local/bin/restore.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh

RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh \
    /usr/local/bin/restore.sh \
    /usr/local/bin/backup.sh
