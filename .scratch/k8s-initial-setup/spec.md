## Problem Statement

The infrastructure repo can run the platform's two backing services as Docker Compose stacks on a Windows laptop, but it cannot run them the way they will run in production. Helm charts written for this platform therefore have nowhere to be tested except Azure, which is slow and expensive to iterate against, and the existing Compose database stack has no production-shaped counterpart at all. Someone preparing a chart for AKS has to guess whether it will work, and a database deployment has no chart to deploy in the first place.

There is also no record of how the platform is meant to be shaped in Kubernetes. The repo has two Compose stacks, one convention document, and no Kubernetes, Helm or deployment artefacts of any kind, so every decision about clusters, storage, ingress and secrets would otherwise be made implicitly and separately by whoever writes the first chart.

## Solution

A local Kubernetes cluster that behaves as much like AKS as a laptop allows, defined as version-pinned configuration and driven by shell scripts from the developer's existing Git Bash terminal, with environment profiles so a second cluster can later emulate production without a rewrite.

A production-shaped Helm chart for the platform's PostgreSQL database that deploys onto that cluster and onto AKS unchanged, with environment-specific values overlays, credentials delivered from HashiCorp Vault rather than hardcoded, a data-safety story based on scheduled dumps, and documented access paths for developers on Windows.

A repeatable test that proves the whole path works: cluster up, secrets flowing, chart installed, data written and read back, data surviving restarts, chart upgrading cleanly, and the cluster removable again.

The work is planned as a spec plus blockers-first tickets under a local markdown tracker, so progress stays visible in the repository.

## User Stories

1. As a platform developer, I want a local Kubernetes cluster I can start from my normal Git Bash terminal, so that I do not have to learn a second toolchain to test infrastructure.
2. As a platform developer, I want the local cluster pinned to a Kubernetes version that AKS currently supports, so that a chart which works locally is not relying on an API that production has removed.
3. As a platform developer, I want the local cluster to have one control plane and two worker nodes, so that node affinity, pod disruption budgets and topology spread behave the way they will in production instead of degenerating on a single node.
4. As a platform developer, I want cluster definitions expressed as profiles, so that adding a second local cluster which emulates production does not mean restructuring the setup.
5. As a platform developer, I want `up`, `down` and `status` commands that are safe to run repeatedly, so that a failed run can be retried without hand-repairing cluster state.
6. As a platform developer, I want the cluster to be reachable only through an explicit named context, so that starting or destroying it can never touch another cluster on my machine.
7. As a platform developer, I want a storage class that behaves like a normal dynamic provisioner, so that persistent volume claims in my charts bind without special-casing the local environment.
8. As a platform developer, I want the cluster to report CPU and memory usage, so that resource requests and limits in my charts can be validated rather than guessed.
9. As a platform developer, I want to serve ordinary Ingress objects locally under the same ingress class name AKS uses, so that charts written for AKS application routing work unchanged.
10. As a platform developer, I want to serve Gateway API routes as well, so that charts written for the direction AKS is heading also work locally.
11. As a platform developer, I want both HTTP ingress contracts available in one cluster, so that I do not have to choose one and maintain two clusters.
12. As a platform developer, I want a certificate manager available locally, so that charts which expect certificates to be issued can be tested, while remembering that AKS itself does not ship one.
13. As a platform developer, I want to publish a plain TCP service to my Windows host on a documented port, so that a database is reachable from my normal client tools without an HTTP ingress in front of it.
14. As a platform developer, I want the database reachable through a port-forward on a documented port, so that the default access path needs no cluster configuration at all.
15. As a platform developer, I want the database's TCP publication to be a toggle in chart values, so that a chart which must not expose the database in production can be installed with the exposure off.
16. As a platform developer, I want database credentials to live in Vault and be synchronised into the cluster, so that no chart in this repository ever carries a credential.
17. As a platform developer, I want a scoped, non-root Vault token used for that synchronisation, so that the cluster cannot read secrets outside the ones it owns even locally.
18. As a platform developer, I want the Vault contents to be re-seeded by a repeatable script, so that the loss of the local in-memory Vault is a re-run rather than an investigation.
19. As a platform developer, I want the secret synchronisation mechanism to be the same shape as the one I would use with Azure Key Vault, so that moving from local to cloud is configuration rather than a rewrite.
20. As a platform developer, I want the database to deploy from a Helm chart with a single install command, so that bringing up a database in any environment is one step.
21. As a platform developer, I want the database chart to expose the same environment variable names the application already reads, so that pointing the application at the cluster requires no application change.
22. As a platform developer, I want separate values files for local, dev and production, so that environment differences are visible in the repository rather than remembered.
23. As a platform developer, I want dev and production values to be honest skeletons naming every key that must be filled, so that an incomplete environment fails loudly instead of silently inheriting laptop defaults.
24. As a platform developer, I want the database's schema to remain owned by the application, so that the chart does not become a second writer racing application migrations.
25. As a platform developer, I want an optional way to apply the existing schema when the application is not running, so that a pre-seeded database is possible without duplicating the schema definition.
26. As a platform developer, I want scheduled dumps with time-based retention and a minimum number kept, so that the safety net cannot silently prune itself to nothing.
27. As a platform developer, I want dump files to keep their existing names, so that dumps taken from the Compose stack and from the cluster remain interchangeable.
28. As a platform developer, I want a documented way to copy dumps out of the cluster onto my Windows filesystem, so that backups remain plain files I can inspect.
29. As a platform developer, I want an explicit, opt-in restore, so that restarting a database never silently rolls back data written since the last dump.
30. As a platform developer, I want the cluster's database and the Compose database to coexist, so that testing the cluster does not require stopping my existing development stack.
31. As a platform developer, I want the application's own environment file left untouched, so that switching between Compose and the cluster is a documented choice rather than a side effect of my work.
32. As a platform developer, I want one automated test that exercises the whole path and reports pass or fail per check, so that "it works" is evidence rather than an opinion.
33. As a platform developer, I want that test to prove data survives a pod deletion and a chart upgrade, so that the data-safety claims are actually verified.
34. As a platform developer, I want the cluster left running when the work is done, along with the exact command that removes it, so that I can inspect the result without paying for another setup run.
35. As a future maintainer, I want the reasoning behind the cluster distribution, the database topology and the local secret store written down, so that deliberate decisions are not "fixed" by someone who assumes the opposite.
36. As a future maintainer, I want a glossary of the project's own terms, so that the words used in tickets and documentation mean one thing.
37. As a future maintainer, I want the repository's convention document to register the new directories, so that the next person finds them without reading git history.
38. As a future maintainer, I want the local cluster setup to be reconstructible from a clean clone using only the documentation, so that the environment is not a machine-specific artefact.

## Implementation Decisions

- **Kubernetes 1.36 on kind 0.33.0.** AKS currently supports three minor versions and defaults new clusters to N-1; 1.34 leaves support this month, and the newest minor is outside the supported range of several components we depend on. 1.36 sits inside the AKS window, inside the certificate manager's supported range and is new enough for the current metrics server. The installed kind is far too old to run anything newer than 1.33 and cannot be used.
- **Three nodes, one control plane and two workers.** Flattens nothing about scheduling behaviour, and fits comfortably in the memory available to the container runtime.
- **Profiles from the first commit, with only the local profile created.** Cluster name, node count, published ports and addon set are profile inputs, so a production-emulating cluster is a second profile rather than a second codebase.
- **Cluster lifecycle is shell scripts, not PowerShell.** The developer works from a Git Bash session; the repository's existing scripts are POSIX shell; and PowerShell 7 is not installed on this machine.
- **Tooling comes from the system package manager, pinned by version in the repository.** Cluster and client binaries are not vendored into the project.
- **Both ingress contracts, one classic controller serving two ingress class names.** One class keeps the familiar local name and the other matches the AKS application routing class exactly, so charts written for either work locally. Upstream ingress-nginx is retired, so the classic contract is served by a maintained controller instead.
- **TCP publication is a Gateway listener where the gateway implementation supports it, with a node-port fallback behind the same host port.** The user-visible contract is one host port; only the mechanism may differ, and the delivered mechanism is documented.
- **The database is never placed behind an HTTP ingress.** PostgreSQL speaks a binary protocol over TCP; an HTTP ingress in front of it is a category error.
- **Vault is revived as the in-memory development instance it already is, and its contents are re-seeded by script.** It has no persistent storage and its volumes are empty; its token is a public placeholder baked into another project's image; and another project already depends on it at the same address. Repairing its durability would change a container this work does not own, so the honesty is in the seed script and in the record, not in pretending persistence.
- **A scoped token is minted for the cluster.** The root token is used only while seeding; the cluster receives a token whose policy reads only this project's paths.
- **External Secrets Operator with the Vault provider, KV version 2, token authentication locally.** The same operator fronts Azure Key Vault in the chart's production story, so the abstraction is the point.
- **A plain StatefulSet chart, with no operator.** This was chosen over an operator-managed high-availability cluster. The consequence is stated rather than hidden: a single writer, no automatic failover, no point-in-time recovery, and scheduled dumps as the safety net. An operator remains the recorded alternative if failover later becomes a requirement.
- **PostgreSQL 17**, matching the existing Compose stack and keeping the existing dumps directly restorable.
- **The chart consumes an existing secret rather than generating a credential.** The application already reads a fixed set of environment variable names; the chart emits exactly those, closing a gap where the application reads a host variable that nothing in the repository currently sets.
- **Values overlays: defaults plus local, dev and production.** Local is complete and working. Dev and production are skeletons that name every required key and fail loudly when unset. The production overlay documents the AKS storage class and ingress class names so local specifics never leak into production.
- **The chart does not own the schema.** The application self-initialises; an optional, off-by-default job can apply the existing schema through a generated configuration object for the case where a pre-seeded database is wanted without the application.
- **Restore is an explicit opt-in job, never an automatic step on start.** The Compose stack's restore-on-every-start behaviour is a development affordance; in Kubernetes it would let a readiness probe go green while a restore is still replaying writes that are about to be overwritten.
- **Dumps are scheduled on wall-clock boundaries with time-based retention and a minimum keep**, deliberately mirroring the contract already proven in the Compose stack rather than inventing a second one.
- **Ports: port-forward on one port, gateway publication on another, leaving the Compose stack's published port alone.** Both were confirmed free on the host.
- **No GitOps and no Terraform.** The setup is scripts and committed manifests; a reconciliation layer can be added later without rewriting either.
- **Recorded as decisions in the repository:** the cluster distribution and version pin, the no-operator database topology with its rejected alternative, and the ephemeral local secret store.

## Testing Decisions

- **Good tests assert externally observable behaviour.** Every check drives the system the way a developer would, through the command line, and asserts what a developer can see: cluster state, object readiness, a real database session, data present after a restart, a successful upgrade. Nothing asserts on internal implementation detail or on rendered template text beyond syntax validity.
- **There is one seam and it is the highest one available:** the shell entrypoints plus the standard cluster, chart and database CLIs. The cluster lifecycle scripts are the only new interface, so the same seam covers bootstrap, verification and teardown, and no test reaches inside a pod to inspect a process.
- **Chart correctness is tested in layers, cheapest first:** lint and template rendering must be clean before anything is installed; a real install into a dedicated namespace must succeed; only then are runtime checks run. This mirrors the repository's existing habit of validating a Compose file before starting it.
- **Prior art is the Compose stack's documented validation loop**, which writes a row, restarts, and observes whether the row survived. The cluster test keeps that shape: write, disturb, observe, and additionally upgrades the release between disturbances.
- **The data-safety claims are tested by falsification, not by observation.** Deleting the pod and confirming the row is still there, and upgrading the release and confirming the row is still there, are the observations that would show the chart's persistence and its use of an existing secret to be wrong.
- **The secret path is tested from the consumer's side.** The test asserts that the cluster holds a credential and that a database session authenticates with it, not that a particular controller object exists.
- **Everything is expressed as one script that prints a pass or fail line per check** and exits non-zero if any check fails, so the whole acceptance bar is one command and its output is the evidence.
- **Teardown is tested too.** A test that can only build is half a test; the setup must return the machine to its previous state.

## Out of Scope

- Running Kafka in the cluster. The pattern is documented; the second stack is not migrated.
- Creating the production-emulating cluster. Only the mechanism that would allow it is built.
- Operator-managed database high availability, automatic failover, point-in-time recovery, write-ahead-log archiving and object-store backups. These are the rejected alternative, recorded in an ADR.
- Azure Key Vault, workload identity and managed-identity wiring. The production overlay documents where they go and stops there.
- Transport security between the cluster and Vault, real Vault initialisation and unseal, and durable Vault storage. The local instance is explicitly a development artefact.
- Reconciling the two existing copies of the database schema. This work deliberately creates no third copy and leaves the divergence for a separate decision.
- Any change to the Compose stacks or to the application repository, including its environment file.
- Continuous integration. The repository has no workflow directory, and adding one is a separate decision.
- Correcting the stale backup configuration text in the repository's convention document.

## Further Notes

- **A client/server version skew is introduced on this machine.** The current client binary is several minors behind the cluster and is being replaced; the replacement is then newer than an existing local cluster profile, whose tooling must be used instead for that profile. This is recorded so the symptom is not mistaken for a defect in this work.
- **The local secret store loses its contents whenever it is restarted**, by construction. The cluster's synchronised secret survives, and the seed script restores the source of truth. Anyone who finds a stale credential after restarting the container should re-run the seed script rather than debug the controller.
- **Both mechanisms that were being verified have now been settled by measurement on this machine.** The gateway implementation can serve a plain TCP listener, but only from the experimental API channel plus an explicit feature flag, and that is what will be installed; the rejected alternative was a node-port mapping behind the same host port. Pods reach the host's secret store through the container runtime's host alias, verified from inside a pod, so no network bridging or hand-written endpoint is needed. One related correction: the classic ingress controller serves exactly one ingress class per installation, so mirroring the AKS class name costs a second installation rather than a second class on the first.
- **Two local capability gaps are recorded rather than discovered later.** The local storage class is read-write-once only and cannot expand, unlike the AKS classes it stands in for, so charts needing shared volumes or volume growth cannot be validated locally. And a published host port accepts a connection even when nothing is behind it, because the runtime forwards to the node before any service is involved, so every reachability check in this work must assert on a real payload instead of a successful connection.
- **The existing Compose stack keeps its ports and its data.** Nothing in this work stops it, and the workspace's two databases are distinguishable by port.
- **The work is tracked but not committed.** The working tree is clean at the current commit; files are added for review, and committing is the developer's decision.
