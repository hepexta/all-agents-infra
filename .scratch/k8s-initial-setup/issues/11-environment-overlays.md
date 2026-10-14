# 11: Environment overlays and the AKS overlay

**What to build:** The chart is installed with one values file per environment, local works out of the box, the development and production files are honest skeletons that fail loudly until filled in, and every cloud-specific detail is confined to the production overlay.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] Installing with the local values file is the documented default path and succeeds without further editing.
- [ ] The development and production files name every key that must be supplied, and an install that leaves a required key unset fails with a message naming it rather than silently inheriting a laptop default.
- [ ] The production overlay references the cloud storage class and the cloud ingress class, and neither name appears in the local overlay.
- [ ] The production overlay documents where cloud secret management and workload identity replace the local secret store, without implementing them.
- [ ] No environment-specific literal, host port or credential appears in the chart's templates; the local specifics live in the local values file only.

**Acceptance evidence:** an install using the local file; a failing install with a required key unset and the message it produced; the three values files; a template scan showing no environment literal.
