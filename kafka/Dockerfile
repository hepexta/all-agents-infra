# all-agents kafka: single-node KRaft Kafka broker with the platform contracts
# baked in (JSON payload schemas + topic definitions + first-boot topic creation).
#
# The wrapper entrypoint (scripts/docker-entrypoint-wrapper.sh) starts the
# official broker, waits until it accepts API connections, then creates the
# platform topics (idempotent, --if-not-exists). Topics live in the KRaft data
# volume, so they survive restarts; topic creation on later starts is a no-op.
#
# Note: --chmod on COPY is required (not a style choice) — on Windows hosts,
# directory COPYs lose the execute bit and a later RUN chmod fails with
# "Operation not permitted" (Docker Desktop containerd image store bug).
# go+rwX restores group/other read + execute-on-directories-only; the container
# runs as the non-root appuser, so the contracts must be world-readable.
FROM apache/kafka:3.9.1

COPY --chmod=go+rwX schemas/ /opt/agents-kafka/schemas/
COPY --chmod=go+rwX topics/ /opt/agents-kafka/topics/

COPY --chmod=755 scripts/docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
COPY --chmod=755 scripts/create-topics.sh /usr/local/bin/create-topics.sh
