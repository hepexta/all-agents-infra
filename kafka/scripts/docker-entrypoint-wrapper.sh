#!/bin/sh
# Wrapper entrypoint: start the official Kafka broker (KRaft single node) in the
# background, wait until it accepts API connections, create the platform topics,
# then keep the container alive as the broker.
#
# Mirrors the agents-database wrapper pattern: INT/TERM are forwarded to the
# backgrounded broker PID so `docker stop` shuts the broker down cleanly.
set -e

# Official image entrypoint + launcher (configures KRaft from env, execs the broker).
/__cacert_entrypoint.sh /etc/kafka/docker/run &
SERVER_PID=$!

forward() {
  kill -TERM "$SERVER_PID" 2>/dev/null || true
}
trap 'forward' INT TERM

# Readiness = a real broker API handshake (listener bound + controller quorum ready).
KAFKA_CLIENT_PORT=${KAFKA_CLIENT_PORT:-9092}
i=0
until /opt/kafka/bin/kafka-broker-api-versions.sh \
    --bootstrap-server "127.0.0.1:${KAFKA_CLIENT_PORT}" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 120 ]; then
    echo "Kafka broker did not become ready within 120s" >&2
    exit 1
  fi
  sleep 1
done

/usr/local/bin/create-topics.sh

wait "$SERVER_PID"
