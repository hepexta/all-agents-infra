# 06: Secrets synchronised into the cluster

**What to build:** A secret authored in the developer's secret store appears in the cluster as a Kubernetes secret without anyone running a fetch command, and returns if it is deleted.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] After installation, a named secret in a dedicated namespace holds the value seeded at the source.
- [ ] Deleting that secret results in it being recreated with the same value without manual intervention.
- [ ] Changing the value at the source is reflected in the cluster within the configured refresh interval.
- [ ] The store reference reads only this project's path prefix and authenticates with the scoped token rather than the administrative one.
- [ ] The controller reports the synchronisation as successful, and no credential appears in any committed file.
- [ ] The mechanism is the same shape as the cloud secret manager path documented for production, so moving between them is configuration rather than a rewrite.

**Acceptance evidence:** the secret's contents matching the source; the deleted-then-recreated secret; a changed source value reflected after refresh; the controller's reported status; a scan showing no credential in the repository.
