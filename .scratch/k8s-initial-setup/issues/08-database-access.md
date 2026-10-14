# 08: Database access paths

**What to build:** A developer reaches the cluster database from Windows on the reserved port with no cluster configuration, or through the cluster gateway when the exposure toggle is on, and can point the application at the cluster without editing the application repository.

**Blocked by:** 04, 07

**Status:** ready-for-agent

- [ ] A documented port-forward command on the reserved port yields a working client session from Windows.
- [ ] With the exposure toggle on, the same session works against the published port, and with the toggle off that port does not serve the database.
- [ ] The exposure setting lives in values rather than in a template, so a production install can forbid it without editing the chart.
- [ ] The database is never placed behind an HTTP ingress in any overlay.
- [ ] The documented switch names the exact settings that move the application between the container stack and the cluster, and applying it requires no change inside the application repository.
- [ ] The documentation states that the application's own environment file is deliberately untouched, and that both databases can run at once because they use different ports.

**Acceptance evidence:** a client session over the forwarded port; a session over the published port with the toggle on and its absence with the toggle off; the values-driven toggle; the documented switch and the untouched environment file.
