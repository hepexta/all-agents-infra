# 08: Database access paths

**What to build:** A developer reaches the cluster database from Windows on the reserved port with no cluster configuration, or through the cluster gateway when the exposure toggle is on, and can point the application at the cluster without editing the application repository.

**Blocked by:** 04, 07

**Status:** ready-for-agent

- [x] A documented port-forward command on the reserved port yields a working client session from Windows.
- [x] With the exposure toggle on, the same session works against the published port, and with the toggle off that port does not serve the database.
- [x] The exposure setting lives in values rather than in a template, so a production install can forbid it without editing the chart.
- [x] The database is never placed behind an HTTP ingress in any overlay.
- [x] The documented switch names the exact settings that move the application between the container stack and the cluster, and applying it requires no change inside the application repository.
- [x] The documentation states that the application's own environment file is deliberately untouched, and that both databases can run at once because they use different ports.

**Acceptance evidence:** a client session over the forwarded port; a session over the published port with the toggle on and its absence with the toggle off; the values-driven toggle; the documented switch and the untouched environment file.

## Comments

- 2026-10-14: the chart gained an exposure toggle, off in the defaults and on only in the local overlay, which attaches the database to the cluster gateway's transport-layer listener. The database is never given an HTTP ingress in any overlay, and that is now checked rather than asserted: no template declares one, none renders one, and the chart contains no HTTP route at all.
- Verified from Windows over both paths. The port-forward on the reserved port carried an authenticated session, and the published port did the same with the toggle on. The evidence for the toggle being real is deliberately recorded as a pair of observations: with the route removed the published port still accepts a raw connection, because the mapping forwards to the node before any routing happens, while a real client session fails with the server closing the connection. A check that only opened a socket would have reported the exposure as still working.
- The port-forward is independent of the exposure setting, which was confirmed while the toggle was off, and the tunnel binds only the loopback address, so no part of this hands the database to the local network.
- The switch between the two databases is a printer rather than an editor. It reads the credential from the cluster and prints the five settings the application already reads, for the cluster through either path or for the container stack, and it writes nothing outside this repository. The application's own environment file is untouched, and the two databases coexist because they use different ports.

