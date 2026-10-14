# 04: Publish a TCP service to the Windows host

**What to build:** A plain TCP service inside the cluster is reachable from Windows client tools on the host port reserved for the database, proving the transport path before the database chart depends on it.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] A throwaway database instance in the cluster is reachable from Windows on the reserved host port using a real client session that authenticates and runs a query.
- [ ] Reachability is proven with a real payload, because a published port accepts a connection even when nothing is behind it.
- [ ] The same instance remains reachable through its in-cluster address, and data written over the published path is visible through the in-cluster path, proving both reach the same instance.
- [ ] When the publication toggle is off, the reserved port does not serve the database.
- [ ] The publication does not disturb the ports already published by the developer's existing container stack.
- [ ] The delivered mechanism is recorded together with the rule that the node port and the published mapping must share a number, and the consequence that the database cannot be reached on the host port the container stack already uses.

**Acceptance evidence:** an authenticated query over the published port; the same row read over the in-cluster address; the toggle-off result; the running container port listing; the mechanism note.
