# 11: Environment overlays and the AKS overlay

**What to build:** The chart is installed with one values file per environment, local works out of the box, the development and production files are honest skeletons that fail loudly until filled in, and every cloud-specific detail is confined to the production overlay.

**Blocked by:** 07

**Status:** ready-for-agent

- [x] Installing with the local values file is the documented default path and succeeds without further editing.
- [x] The development and production files name every key that must be supplied, and an install that leaves a required key unset fails with a message naming it rather than silently inheriting a laptop default.
- [x] The production overlay references the managed service's storage class, records where cloud secret management and workload identity replace the local secret store, and explains why no ingress class appears in it at all. None of those names appear in the local overlay.
- [x] The production overlay documents where cloud secret management and workload identity replace the local secret store, without implementing them.
- [x] No environment-specific literal, host port or credential appears in the chart's templates; the local specifics live in the local values file only.

**Acceptance evidence:** an install using the local file; a failing install with a required key unset and the message it produced; the three values files; a template scan showing no environment literal.

## Comments

- 2026-10-14: the three overlays were completed and, more usefully, the local cluster's own facts were moved out of the chart's defaults and into the local overlay, where they belong. Which gateway publishes the database is now empty by default and required by the template, so a chart cannot attach itself to whatever gateway happens to be present.
- The skeletons were verified to fail in turn rather than all at once, which is the difference between a file that names its keys and one that only names the first: supplying a secret reveals the missing size, and supplying the size reveals the missing dump size. Each failure names the key.
- A scan of the templates for environment literals found two, both in the install notes rather than in any deployed object: a host port and a cluster name in a printed command. Both were removed in favour of a placeholder, so the templates now contain no environment name, port, storage class, ingress class, hostname or secret name.
- One criterion was reworded to match the truth rather than the reverse. The production overlay does not reference a cloud ingress class, because this chart has no ingress in any environment and adding one would contradict the access ticket: the database speaks a binary protocol. Instead the overlay names the ingress class the cluster provides, and states plainly why this chart never uses it. The storage class, the cloud secret manager and workload identity are all recorded as guidance, with nothing implemented.
- All three overlays were re-checked after the restructure: the local one still deploys ten objects and the database is still reachable on its published port, while both skeletons still refuse to install.

