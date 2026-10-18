# 07: Database chart runs with Vault-backed credentials

**What to build:** The database installs from a single chart command into the cluster, runs on the pinned major version, persists its data through a bound claim, authenticates with the credential delivered from the secret store, and publishes the connection settings the application already reads.

**Blocked by:** 02, 06

**Status:** ready-for-agent

- [x] Linting and template rendering of the chart are clean, including with the local values file.
- [x] One install command brings up a single-primary instance whose pod reaches ready with no manual step, and running the same command twice is idempotent.
- [x] The claim is bound, and the data directory is not on the container's ephemeral filesystem.
- [x] A client session authenticates with the credential that came from the secret store, and is refused when given a wrong credential.
- [x] The chart publishes host, port, database, user and password under the exact names the application already reads, closing the existing gap where the host name is read but never set.
- [x] The instance runs as a non-root user, with resource requests and limits, readiness and liveness probes, a disruption budget, and anti-affinity that keeps additional replicas off a node already running one.
- [x] The chart never generates or embeds a credential and requires an existing secret to be supplied instead.
- [x] The absence of an operator, and therefore of automatic failover and point-in-time recovery, is recorded as a deliberate decision with the rejected alternative named.

**Acceptance evidence:** lint and render output; install and second install; claim status; the successful and refused client sessions; the published settings; the workload specification showing the security, resource, probe and scheduling settings; the decision record.

## Comments

- 2026-10-14: the chart was written into a new subdirectory beside the existing Compose stack, which is untouched. It deploys a single primary on the pinned major version behind a service and a stable headless service, with a claim from a template, a disruption budget, preferred anti-affinity, a security context, probes, resource settings and a connection ConfigMap. Versions: chart 0.1.0, application version 17.
- Linting is clean and rendering produces five objects. Two defects in my own work were found and fixed while checking: the version floor in the chart metadata claimed the version the chart had been tested against rather than the version it requires, which made rendering fail for the wrong reason, and the connection test deleted its own pod on success, taking the evidence with it.
- The install command was run twice with no manual intervention; afterwards there is exactly one stateful set, one pod and one claim, so the second run upgraded rather than duplicated. The claim is bound to a provisioned volume, and the only empty directories on the pod are for the socket and temporary files: the data directory is the claim.
- The credential in use was compared against the secret store by fingerprint and matches, and no file in the chart contains that value. A search that appeared to find a credential turned out to be matching the mapping that says which key inside the secret holds the password, which is a reference rather than a value.
- The connection test the chart ships with asserts both halves: it authenticates with the delivered credential, reporting the user and database it reached, and it confirms that a wrong credential is refused. A test that checked only the first half would pass against a server with authentication disabled.
- The guard that keeps the environment overlays honest was exercised rather than assumed: installing with either skeleton fails, and the failure names the key that must be supplied instead of quietly falling back to a laptop default.
- The decision to run without an operator, and therefore without automatic failover or point-in-time recovery, is recorded as a decision record with the rejected alternative named, so that the gap is a choice rather than an oversight.

