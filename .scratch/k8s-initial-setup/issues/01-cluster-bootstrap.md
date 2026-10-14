# 01: Local cluster bootstrap and teardown

**What to build:** A developer can create the local cluster profile from a Git Bash session and remove it again, using only repository scripts. The cluster runs one control plane and two workers on the pinned Kubernetes minor version, is reachable through a context dedicated to this profile, and the scripts are safe to run repeatedly. Cluster name, node count, version and published ports are profile inputs, so a second cluster can be added later without changing script logic.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The up command, run from a clean state, produces a cluster whose every node is Ready, with one control plane and two workers at the pinned minor version.
- [ ] The cluster is reachable only through a context dedicated to this profile, and the developer's pre-existing contexts and clusters are unchanged after both up and down.
- [ ] Running up twice in succession succeeds and reports the cluster already present rather than creating a second one.
- [ ] The status command reports cluster presence, node count and version without modifying anything.
- [ ] The down command removes the cluster and its context and leaves no containers attributable to it, and running it twice is harmless.
- [x] The profile name, cluster name, node count, node image and published ports are inputs rather than constants.
- [x] A readme covers the commands, the knobs and the teardown, and an architecture decision record records why this distribution and this pinned version were chosen over the alternatives.

**Acceptance evidence:** node listing with versions and roles; context listing before and after; second consecutive up run; down run followed by a container listing; the readme and the decision record.

## Comments

- 2026-10-14: scripts, profile, readme and decision record written and their mechanics verified from Git Bash without creating a cluster. `status.sh` reports profile, cluster, context and an absent state. `up.sh --render-only` renders the expected three node configuration with the digest pinned image and the three host port mappings. The kind version guard refuses the installed 0.29.0 with an actionable message rather than building a cluster whose nodes never become Ready. Three negative cases fail cleanly with non-zero exits: a host port outside the node port range, two control plane nodes, and an unknown profile. `down.sh` reports nothing to delete and exits zero while the cluster is absent.
- Remaining criteria need a live cluster and are blocked on upgrading kind to 0.33.0, which requires an elevated shell: `choco upgrade kind -y`.

