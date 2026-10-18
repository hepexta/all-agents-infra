# 02: Storage class and metrics

**What to build:** A workload in the cluster can claim durable storage through the default class without naming it, and the cluster reports real CPU and memory usage so that resource settings in a chart can be checked against numbers instead of guesses.

**Blocked by:** 01

**Status:** ready-for-agent

- [x] A claim created without naming a class binds through the cluster's default class and is writable by a pod.
- [x] Deleting and recreating the pod leaves a file written earlier still present, proving the volume is not ephemeral.
- [x] Usage reporting for nodes, and for at least one pod, returns non-empty CPU and memory figures.
- [x] The default class name, and its two limitations of read-write-once only and no volume expansion, are documented next to the cloud class it stands in for.
- [x] Neither capability is silently assumed elsewhere: any place expecting shared storage or growth records that it is unverified locally.

**Acceptance evidence:** claim status and bound volume; file listing before and after pod recreation; usage output; the documented storage comparison.

## Comments

- 2026-10-14: metrics-server chart 3.14.0 installed from a pinned version, reporting usage for all three nodes and for pods in the cluster. Its values file disables kubelet certificate verification, which is required on kind and is flagged there as something that must not travel to a managed cluster.
- Storage verified with the committed check. A claim naming no class bound to `standard`, provisioned by the local path provisioner; the bound volume reports read-write-once only and no expansion; it carries a node affinity that pulled the replacement pod back onto the same node it was created on. The writer pod left a marker in the volume, and a brand new pod mounting the same claim read it back, so the volume is genuinely persistent rather than ephemeral.
- Nothing in this work depends on shared storage or on growing a claim, so the two limitations are recorded as capability gaps rather than scheduled work. The database chart uses a single read-write-once claim.
- One Windows trap caught by this ticket, twice in the same run: an argument that is a path inside a container is rewritten by the shell before the Windows client sees it, so the read of the marker failed with a message about a host directory while the volume was perfectly healthy. Every such command now carries the path conversion guard, and the readme explains the failure so it is not mistaken for a storage fault.

