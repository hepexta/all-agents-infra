# 06: Secrets synchronised into the cluster

**What to build:** A secret authored in the developer's secret store appears in the cluster as a Kubernetes secret without anyone running a fetch command, and returns if it is deleted.

**Blocked by:** 05

**Status:** ready-for-agent

- [x] After installation, a named secret in a dedicated namespace holds the value seeded at the source.
- [x] Deleting that secret results in it being recreated with the same value without manual intervention.
- [x] Changing the value at the source is reflected in the cluster within the configured refresh interval.
- [x] The store reference reads only this project's path prefix and authenticates with the scoped token rather than the administrative one.
- [x] The controller reports the synchronisation as successful, and no credential appears in any committed file.
- [x] The mechanism is the same shape as the cloud secret manager path documented for production, so moving between them is configuration rather than a rewrite.

**Acceptance evidence:** the secret's contents matching the source; the deleted-then-recreated secret; a changed source value reflected after refresh; the controller's reported status; a scan showing no credential in the repository.

## Comments

- 2026-10-14: the operator was installed with its custom resources applied server side, since they exceed the annotation size limit and the chart's own copy cannot be used for that reason. A cluster-scoped store points at the local secret store, and an external secret in the database namespace derives the credential the chart will consume.
- Verified: the derived secret holds all three keys with values identical to the source, and it is owned by its external secret rather than created alongside it. Deleting the derived secret produced it again with the same value and no intervention. Rotating the credential at the source was followed by the cluster without any command being run. The store and the external secret both report themselves ready. No credential appears in any tracked file, and the scoped token file is ignored by version control.
- One real defect surfaced and was fixed at its cause: the token file's trailing newline travelled into the secret and the operator rejected the store as holding non-printable characters, which reads like a bad credential rather than a stray byte. The install script now trims it, and both scripts record why. A second, subtler lesson is recorded in the readme: the operator revalidates a store on a backoff, so a wait that expires after a previously invalid store is not evidence that the fix did not work.
- The production story is deliberately a configuration swap rather than a rewrite: the same operator fronts a cloud secret manager with workload identity, and the token disappears. That path is documented in the chart's production overlay rather than implemented here.

