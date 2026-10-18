# 01: Local cluster bootstrap and teardown

**What to build:** A developer can create the local cluster profile from a Git Bash session and remove it again, using only repository scripts. The cluster runs one control plane and two workers on the pinned Kubernetes minor version, is reachable through a context dedicated to this profile, and the scripts are safe to run repeatedly. Cluster name, node count, version and published ports are profile inputs, so a second cluster can be added later without changing script logic.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] The up command, run from a clean state, produces a cluster whose every node is Ready, with one control plane and two workers at the pinned minor version.
- [x] The cluster is reachable only through a context dedicated to this profile, and the developer's pre-existing contexts and clusters are unchanged after both up and down.
- [x] Running up twice in succession succeeds and reports the cluster already present rather than creating a second one.
- [x] The status command reports cluster presence, node count and version without modifying anything.
- [x] The down command removes the cluster and its context and leaves no containers attributable to it, and running it twice is harmless.
- [x] The profile name, cluster name, node count, node image and published ports are inputs rather than constants.
- [x] A readme covers the commands, the knobs and the teardown, and an architecture decision record records why this distribution and this pinned version were chosen over the alternatives.

**Acceptance evidence:** node listing with versions and roles; context listing before and after; second consecutive up run; down run followed by a container listing; the readme and the decision record.

## Comments

- 2026-10-14: scripts, profile, readme and decision record written and their mechanics verified from Git Bash without creating a cluster. `status.sh` reports profile, cluster, context and an absent state. `up.sh --render-only` renders the expected three node configuration with the digest pinned image and the three host port mappings. The kind version guard refuses the installed 0.29.0 with an actionable message rather than building a cluster whose nodes never become Ready. Three negative cases fail cleanly with non-zero exits: a host port outside the node port range, two control plane nodes, and an unknown profile. `down.sh` reports nothing to delete and exits zero while the cluster is absent.
- 2026-10-14: kind upgraded to 0.33.0 and the client to 1.37.1, and the whole cycle was then exercised live. Creation produced one control plane and two workers, all Ready at v1.36.4. A second up run reported the cluster already present and `kind get clusters` still listed exactly one. Status reported presence, three nodes and server v1.36.4. Down removed the cluster, left no containers matching the project name, and a second down reported nothing to delete with exit zero. The current context was pointed at a pre-existing context before recreation, and up restored it afterwards, so no other cluster is disturbed. The kubeconfig was returned to the state it was found in.
- Host port bindings on the control plane are the seven the profile declares, all bound to the loopback address, with the API server on a random port as kind intends. The cluster's default storage class is the bundled one named `standard`, provisioned by the local path provisioner with delayed binding and expansion disabled, which is the capability gap the storage ticket has to work within.
- One Windows trap found and fixed while validating: raw API paths passed to the Windows client are rewritten by the shell before kubectl sees them, so the health check in the readme now carries the same path conversion guard the convention document already prescribes for container paths.


