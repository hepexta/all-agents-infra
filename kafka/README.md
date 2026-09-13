# agents-kafka

Single-node KRaft Kafka broker for the all-agents platform's async processing
pipeline (sibling repo `C:\Work\Projects\AI\all-agents`). REST endpoints publish
processing requests; agents consume them and publish completion events; the UI
listens for job-done events and refreshes from chat history.

## Usage

```bash
cd kafka
docker compose up -d --build   # build + start the broker, topics created on first start
docker compose ps              # wait for agents-kafka to be (healthy)
docker compose config --quiet  # validate compose file after edits
docker compose logs agents-kafka
docker compose down            # graceful stop
docker compose down -v         # wipes the broker volume (topics + messages)
```

Env knobs (compose, defaults inline): `KAFKA_PORT` (9092),
`KAFKA_ADVERTISED_HOST` (localhost). No `.env` file exists.

Consume what the app produces (handy for debugging):

```bash
docker exec -it agents-kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic agent-events --from-beginning
```

## Contracts (kept in both repos)

The payload schemas and topic definitions are the wire contract between this
stack and the all-agents backend. The mirror in the app repo is
`all-agents/contracts/kafka/` — **keep the two copies in sync**; a topic or
schema change must land in both repos.

| File | Content |
|---|---|
| `schemas/processing-request.schema.json` | `ProcessingRequest` payload of `agent-requests` (key = processingId) |
| `schemas/agent-event.schema.json` | `AgentEvent` payload of `agent-events` (key = correlationId \| agent name) |
| `topics/topics.txt` | `<name> <partitions> <retention.ms>` per line, applied idempotently on every start |

## How it runs

- `Dockerfile` layers the contracts + init scripts onto `apache/kafka:3.9.1`
  (single-node KRaft, `KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`).
- `docker-entrypoint-wrapper.sh` replaces the entrypoint: it backgrounds the
  official launcher (`/__cacert_entrypoint.sh /etc/kafka/docker/run`), waits for
  a real broker API handshake (`kafka-broker-api-versions.sh`), then creates the
  topics. INT/TERM are forwarded to the broker PID for a clean `docker stop`.
- `create-topics.sh` is idempotent (`--if-not-exists`) and re-runs on every
  start; topics themselves live in the `kafkadata` volume.

## Validation

```bash
docker compose down -v
docker compose up -d --build
docker compose ps                          # (healthy) means the broker is up
docker exec agents-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
# → agent-events, agent-requests
```
