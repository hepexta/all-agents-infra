# 07: Database chart runs with Vault-backed credentials

**What to build:** The database installs from a single chart command into the cluster, runs on the pinned major version, persists its data through a bound claim, authenticates with the credential delivered from the secret store, and publishes the connection settings the application already reads.

**Blocked by:** 02, 06

**Status:** ready-for-agent

- [ ] Linting and template rendering of the chart are clean, including with the local values file.
- [ ] One install command brings up a single-primary instance whose pod reaches ready with no manual step, and running the same command twice is idempotent.
- [ ] The claim is bound, and the data directory is not on the container's ephemeral filesystem.
- [ ] A client session authenticates with the credential that came from the secret store, and is refused when given a wrong credential.
- [ ] The chart publishes host, port, database, user and password under the exact names the application already reads, closing the existing gap where the host name is read but never set.
- [ ] The instance runs as a non-root user, with resource requests and limits, readiness and liveness probes, a disruption budget, and anti-affinity that keeps additional replicas off a node already running one.
- [ ] The chart never generates or embeds a credential and requires an existing secret to be supplied instead.
- [ ] The absence of an operator, and therefore of automatic failover and point-in-time recovery, is recorded as a deliberate decision with the rejected alternative named.

**Acceptance evidence:** lint and render output; install and second install; claim status; the successful and refused client sessions; the published settings; the workload specification showing the security, resource, probe and scheduling settings; the decision record.
