# agents-database

PostgreSQL for the all-agents platform, packaged as a Helm chart. Installable into the local cluster in this repository and into a managed cluster with the same chart, differing only by which values file is used.

This chart is the Kubernetes counterpart of the Compose stack in the parent directory. The two coexist: the stack publishes its database on the host's own port, and this chart's local overlay publishes nothing unless asked.

## What it deploys

- A **single primary** StatefulSet on PostgreSQL 17, with a bound claim, a service, a stable headless service, a pod disruption budget and preferred anti-affinity.
- A **ConfigMap** publishing `POSTGRES_HOST` and `POSTGRES_PORT`, the non-secret half of the connection settings, under the names the application already reads.
- **No credential of its own.** The chart requires a secret to be named, and consumes `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` from it.
- **No schema.** The application initialises itself; there is no second writer.
- **No restore on start.** Restoring is a deliberate action, never a side effect of a restart.

There is no operator, so there is **no automatic failover and no point-in-time recovery**. Data safety is the scheduled dump. The reasoning is recorded in `../../docs/adr/0004-single-primary-database-without-an-operator.md`.

## Install

From a Git Bash session, with the cluster running:

```bash
sh database/chart/install.sh local
```

That is a `helm upgrade --install` into the `database` namespace, waiting for the database to become ready. The credentials must already exist in that namespace; on the local cluster they are delivered from the local secret store by the cluster setup in `../../k8s-cluster`.

To install by hand instead:

```bash
helm upgrade --install agents-db database/chart \
  --kube-context kind-agents-infra-local \
  --namespace database --create-namespace \
  --values database/chart/values-local.yml --wait
```

## Connect

In cluster, by the service name the ConfigMap publishes:

```
agents-db:5432
```

From Windows, through a port-forward:

```bash
kubectl --context kind-agents-infra-local -n database port-forward svc/agents-db 15432:5432
```

No database client is installed on Windows, so the quickest session is through the client inside the Compose container:

```bash
kubectl --context kind-agents-infra-local -n database get secret agents-db-credentials \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d > /tmp/pgpass
docker exec -i -e PGPASSWORD="$(cat /tmp/pgpass)" agents-db \
  psql -h host.docker.internal -p 15432 -U agents -d allagents -c '\dt'
rm -f /tmp/pgpass
```

### The published port

With the local overlay, the chart also attaches the database to the cluster gateway's transport-layer listener, which the cluster publishes on **15433**. It is the same database on a second address, and it exists so the application can reach it without a tunnel running in another window.

The exposure is a value, never a template change:

```bash
helm upgrade --install agents-db database/chart --kube-context kind-agents-infra-local \
  -n database --values database/chart/values-local.yml \
  --set access.gatewayTcp.enabled=false --wait
```

With it off, the route object disappears and the database is only reachable from inside the cluster. One thing is worth knowing before testing this by hand: **the published port still accepts a connection once the route is gone**, because the mapping forwards to the node before any routing is involved. The only honest check is a real session, which then fails with the server closing the connection.

The default is off, so a managed install that forgets to say otherwise exposes nothing; only the local overlay turns it on.

### Switching the application between the two databases

`connect.sh` prints the settings for whichever database is wanted, including the credential read from the cluster, and writes nothing outside this repository:

```bash
sh database/chart/connect.sh forward     # the cluster, through the port-forward on 15432
sh database/chart/connect.sh published   # the cluster, on the published port 15433
sh database/chart/connect.sh compose     # the container stack, on its own port
```

The application reads `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER` and `POSTGRES_PASSWORD`, so those five values are the entire switch, and applying them requires no change inside the application's repository. Its own environment file is deliberately untouched, and both databases can run at once because they use different ports.

## Wire an application to it

A consumer needs both halves, and gets all five names the application reads:

```yaml
envFrom:
  - configMapRef:
      name: agents-db-connection
  - secretRef:
      name: agents-db-credentials
```

## Values

| Key | Meaning |
| --- | --- |
| `fullnameOverride` | Name of the resources; consumers refer to the database by it |
| `image.repository`, `image.tag` | The server image, pinned in the defaults |
| `auth.existingSecret` | **Required.** Secret holding the credential keys |
| `auth.secretKeys.*` | Which keys inside that secret hold the user, password and database |
| `persistence.size` | **Required.** Claim size |
| `persistence.storageClassName` | Empty means the cluster's default class |
| `resources.*` | Requests and limits for the server |
| `probes.*` | Startup, readiness and liveness timings |
| `podDisruptionBudget.*` | Keeps the only pod from being drained away |
| `antiAffinity.enabled` | Pushes any additional replica onto another node |
| `postgresql.maxConnections` | Server connection limit |
| `postgresql.initdbArgs` | Applied only when the data directory is first created |
| `connection.publish` | Publishes the host and port ConfigMap |

## Dumps

A scheduled job takes a `pg_dump` in the same custom format, with the same file naming and the same retention rules as the container stack, onto a claim of its own beside the data. A dump taken in either place restores in the other.

| Value | Default | Meaning |
| --- | --- | --- |
| `backup.enabled` | `true` | Whether the job and its claim exist at all |
| `backup.schedule` | `0 * * * *` | Hourly on the hour, the cadence the stack also uses |
| `backup.retentionHours` | `48` | Older than this is pruned |
| `backup.minKeep` | `3` | Except that the newest few are always kept |
| `backup.staleSentinelMinutes` | `120` | How long a sentinel from a dead restore is obeyed |
| `backup.persistence.size` | `5Gi` | Space for the dumps themselves |

Three behaviours are deliberate and worth knowing before trusting them:

- **Two dumps never run at once**, because the job forbids concurrency. A slow dump is not overtaken by the next scheduled one.
- **A dump is skipped while a restore is in progress**, using the same sentinel file the container stack uses, so a half-restored database is never captured.
- **A stale sentinel is ignored** after a couple of hours, so a restore that dies cannot stop backups for ever.

Fetch the newest dump onto Windows, where it lands beside the ones the container stack writes:

```bash
sh database/chart/fetch-dump.sh
```

The folder is ignored by version control for dump files, so nothing here gets committed.

## Restore

Restoring is an explicit act, never a side effect of installing, upgrading or restarting:

```bash
sh database/chart/restore.sh --list                            # what is available
sh database/chart/restore.sh allagents-20261014T190107Z.dump   # replace the database with it
```

That script renders the job from the chart, applies it, waits for it, shows its output and removes it. The job is deliberately not part of the release, for two reasons: a job that has already run cannot be modified, so a release-managed one would break every later upgrade, and keeping it out of the release is what makes it impossible for an install to restore anything by accident.

## Schema

The chart does not own the schema. The application initialises itself, and a chart that also created tables would be a second writer racing the first. For a pre-seeded database without the application running, an explicit job applies the platform schema:

```bash
sh database/chart/init-schema.sh
```

The definition is not copied into this chart. The script builds a configuration object from the one existing definition in the parent directory and mounts it into the job, so the repository keeps a single copy that cannot drift.

Restarting or upgrading the database never rolls anything back. That is the one place this chart deliberately differs from the container stack, whose entrypoint restores the newest dump on every start; in a cluster that would let a readiness probe report the database as available while a restore was still overwriting writes.

## Environments

| File | State |
| --- | --- |
| `values.yaml` | Defaults, environment-neutral |
| `values-local.yml` | Complete, and the only one that works without editing |
| `values-dev.yml` | Skeleton: names every key that must be filled in |
| `values-prod.yml` | Skeleton, and records the managed service's storage class |

The development and production files are deliberately unusable as they stand. An install that leaves a required key empty fails and names the key, rather than quietly inheriting a laptop default:

```bash
helm template agents-db database/chart --values database/chart/values-dev.yml
# Error: execution error at (agents-database/templates/_helpers.tpl:...):
# auth.existingSecret must name an existing secret holding the database credentials
```

Filling in one required key reveals the next rather than letting the install proceed with a gap, so the three of them are enforced in turn:

| Required key | Fails with |
| --- | --- |
| `auth.existingSecret` | "must name an existing secret holding the database credentials" |
| `persistence.size` | "must be set for this environment" |
| `backup.persistence.size` | "must be set for this environment" |

The production overlay also records the two cloud substitutions that replace the local secret path: the operator is pointed at the cloud secret manager rather than a local store, and a static token gives way to workload identity. Neither is implemented here. It names the managed service's storage class, and explains why no ingress class appears anywhere in it: the database is never behind an HTTP ingress in any environment.

Facts that belong to one cluster rather than to the chart, such as which gateway publishes the database, live in that environment's file. The local overlay carries them; the defaults leave them empty and the template refuses to render without them, so a chart can never silently attach itself to whatever gateway happens to be there.
