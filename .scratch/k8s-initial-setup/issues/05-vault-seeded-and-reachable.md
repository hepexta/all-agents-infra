# 05: Vault revived, seeded and reachable

**What to build:** The developer's local secret store runs again, holds this project's per-environment secrets under its own paths, issues a token scoped to reading only those paths, and is reachable from inside the cluster.

**Blocked by:** 01

**Status:** ready-for-agent

- [x] The secret store runs and reports healthy on the address the developer's pre-existing project already expects, and that project still finds it there.
- [x] A repeatable seed script writes this project's local secrets, and a second run leaves the same values rather than duplicating or silently rotating them.
- [ ] The cluster receives a token whose policy permits reading this project's paths and denies a path outside them, shown by a successful read and a refused read.
- [ ] A pod in the cluster reads a seeded path successfully, proving the path from cluster to host.
- [x] The seed script is documented as the recovery step after a restart of the secret store.
- [x] The record states plainly that the local store keeps nothing across a restart, that its administrative token is a public placeholder belonging to another project, and why repairing durability was deliberately not undertaken.

**Acceptance evidence:** health response; seeded read output; the scoped read succeeding and the out-of-scope read being refused; the pod-side read; the decision record.

## Comments

- 2026-10-14: the container was started and reports healthy and unsealed on its usual address (server 1.15.0), still named as the other project expects. Seeding works and is idempotent: two consecutive runs left the credential fingerprint unchanged. The scoped token read its own path successfully and was refused a path outside its prefix, with the policy visible as `agents-infra-local-read` and a period of 720h. The key value engine at the mount is version 2 as the synchronisation controller requires.
- Two criteria remain, both needing a live cluster: handing the token to the cluster, and proving a pod can read a seeded path. Both are blocked on upgrading kind to 0.33.0.

