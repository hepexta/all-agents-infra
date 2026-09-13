#!/bin/sh
# Creates the platform topics defined in /opt/agents-kafka/topics/topics.txt.
# Idempotent: runs on every container start, --if-not-exists makes re-runs no-ops.
# Line format: <name> <partitions> <retention.ms>  (# starts a comment)
set -e

BOOTSTRAP=${KAFKA_BOOTSTRAP_SERVERS:-127.0.0.1:9092}
REPLICATION_FACTOR=${KAFKA_REPLICATION_FACTOR:-1}
TOPICS_FILE=${TOPICS_FILE:-/opt/agents-kafka/topics/topics.txt}

kafka_topics() {
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" "$@"
}

while read -r name partitions retention; do
  [ -z "$name" ] && continue
  case "$name" in
    \#*) continue ;;
  esac
  echo "Ensuring topic $name (partitions=${partitions:-3}, retention.ms=${retention:-86400000}, replication-factor=$REPLICATION_FACTOR)"
  kafka_topics --create --if-not-exists \
    --topic "$name" \
    --partitions "${partitions:-3}" \
    --replication-factor "$REPLICATION_FACTOR" \
    --config "retention.ms=${retention:-86400000}"
done < "$TOPICS_FILE"

echo "Platform topics:"
kafka_topics --list
