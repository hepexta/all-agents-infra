# 02: Storage class and metrics

**What to build:** A workload in the cluster can claim durable storage through the default class without naming it, and the cluster reports real CPU and memory usage so that resource settings in a chart can be checked against numbers instead of guesses.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] A claim created without naming a class binds through the cluster's default class and is writable by a pod.
- [ ] Deleting and recreating the pod leaves a file written earlier still present, proving the volume is not ephemeral.
- [ ] Usage reporting for nodes, and for at least one pod, returns non-empty CPU and memory figures.
- [ ] The default class name, and its two limitations of read-write-once only and no volume expansion, are documented next to the cloud class it stands in for.
- [ ] Neither capability is silently assumed elsewhere: any place expecting shared storage or growth records that it is unverified locally.

**Acceptance evidence:** claim status and bound volume; file listing before and after pod recreation; usage output; the documented storage comparison.
