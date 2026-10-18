# 04: Publish a TCP service to the Windows host

**What to build:** A plain TCP service inside the cluster is reachable from Windows client tools on the host port reserved for the database, proving the transport path before the database chart depends on it.

**Blocked by:** 03

**Status:** ready-for-agent

- [x] A throwaway database instance in the cluster is reachable from Windows on the reserved host port using a real client session that authenticates and runs a query.
- [x] Reachability is proven with a real payload, because a published port accepts a connection even when nothing is behind it.
- [x] The same instance remains reachable through its in-cluster address, and data written over the published path is visible through the in-cluster path, proving both reach the same instance.
- [x] When the publication toggle is off, the reserved port does not serve the database.
- [x] The publication does not disturb the ports already published by the developer's existing container stack.
- [x] The delivered mechanism is recorded together with the rule that the node port and the published mapping must share a number, and the consequence that the database cannot be reached on the host port the container stack already uses.

**Acceptance evidence:** an authenticated query over the published port; the same row read over the in-cluster address; the toggle-off result; the running container port listing; the mechanism note.

## Comments

- 2026-10-14: the gateway gained a transport-layer listener on 5432 wired to node port 30433, which the profile publishes as host port 15433. The listener is part of the cluster definition even with nothing attached, so the database chart attaches a route rather than inventing a port.
- Verified in both directions against a throwaway database. A row written over the published host port was read back through the in-cluster service address, and a row written in the cluster was read back over the published port, with both paths reporting the same two rows. Removing the route stopped the database being served on the published port, while the raw socket still opened.
- The trap that this ticket exists to guard against is now demonstrated rather than described: with no route attached, a raw TCP connection to the published port succeeds and a real client session fails with the server aborting the request. A port check alone would have declared this working from the very beginning.
- No database client is installed on Windows, so the client used is the one inside the developer's existing container stack. That is a genuine external client from the cluster's point of view, and it works because a container here can reach a host port bound to the loopback address. The client choice is recorded in the readme next to the check.
- The existing container stack is undisturbed: it still owns its own host port, still reports healthy, and still answers queries on it. The two databases are distinguishable by port alone.

