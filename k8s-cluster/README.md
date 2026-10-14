# k8s-cluster

A local Kubernetes cluster shaped as closely like the managed cluster as a laptop allows, for testing the Helm charts in this repository before they reach Azure.

It is a third sibling of the two container stacks: `database/` and `kafka/` run in Docker Desktop, and this directory runs a real cluster in Docker Desktop. The two coexist, so nothing here requires stopping them.

## What it is

- **kind**, running Kubernetes **1.36.4**, one control plane and two worker nodes.
- Version-pinned by node image digest, so a run months from now produces the same cluster.
- Addressed through a context dedicated to this cluster; your other contexts are left alone, including whichever one is current.
- Cluster name, node count, Kubernetes version and published ports are all **profile inputs**. The scripts hold no cluster name or port of their own, so a second profile is a second file.

## Requirements

- Docker Desktop running with Linux containers.
- `kind` **0.33.0 or newer**. Older releases cannot run node images for Kubernetes 1.36 and later: they do not report an error, they build a cluster whose nodes never become Ready. The scripts refuse to run on an older kind and say so.
- `kubectl` within one minor version of 1.36.

On Windows both are installed with Chocolatey, which needs an elevated shell:

```powershell
choco upgrade kind -y
choco upgrade kubernetes-cli -y
```

## Use

From a Git Bash session:

```bash
cd k8s-cluster

sh scripts/up.sh                 # create the local cluster (idempotent)
sh scripts/status.sh             # report state, nodes and server version
sh scripts/down.sh               # remove the cluster (idempotent)
```

Any profile can be named explicitly, and the default is `local`:

```bash
sh scripts/up.sh local
```

To review what a profile produces without touching the container runtime, add `--render-only`. It writes the kind configuration and prints it, then stops:

```bash
sh scripts/up.sh local --render-only
```

Everything addressed to the cluster should name the context rather than rely on whichever one is current:

```bash
kubectl --context kind-agents-infra-local get pods -A
```

Creating the cluster would normally make it your current context. These scripts remember what your current context was and restore it, so your other clusters stay the default.

## Knobs

All of them live in `profiles/<name>.env`:

| Input | Meaning |
| --- | --- |
| `CLUSTER_NAME` | Cluster name; the context becomes `kind-<name>` |
| `KUBERNETES_VERSION` | The version being pinned, for reporting |
| `NODE_IMAGE` | Node image, pinned by digest |
| `CONTROL_PLANE_NODES` | Must be 1; kind supports one in this setup |
| `WORKER_NODES` | Number of worker nodes |
| `HOST_PORTS` | `host:node` pairs published to the host |
| `LISTEN_ADDRESS` | Interface the published ports bind to, loopback by default |

Published ports in the `local` profile:

| Host | Node | Purpose |
| --- | --- | --- |
| 80 | 30080 | HTTP ingress |
| 443 | 30443 | HTTPS ingress |
| 15433 | 30433 | Database through the cluster gateway, off by default |

Two things about publishing worth knowing before changing that list. The container port **is** the node port, so it has to be inside the node port range, which is why the database cannot appear on the port the container stack already uses. And changing the list requires recreating the cluster: kind only applies port mappings at creation time.

The database port-forward on **15432** needs no mapping at all, because it is tunnelled through the API server.

## Secrets

The database credentials live in HashiCorp Vault rather than in this repository, and reach the cluster through a synchronisation controller instead of a committed file. The store is a container owned by another project, so nothing here creates or configures it beyond starting it and waiting until it answers.

```bash
sh scripts/vault-up.sh                    # start the store if it is stopped, wait until it answers
sh scripts/vault-seed.sh                  # seed this profile's credentials and mint a scoped token
sh scripts/vault-seed.sh local --rotate   # replace the credential instead of keeping it
```

The profile name doubles as the environment name, so the `local` profile writes to `secret/agents-infra/local/database` and a later profile writes its own prefix. The scoped token is written to `.generated/vault-<profile>-token`, which version control ignores.

**After the store is restarted, run `scripts/vault-seed.sh` again.** The store keeps everything in memory, so its contents are gone the moment the container stops; that is a property of the instance, not a defect in this setup. Re-seeding restores the same credential, because an existing password is kept unless `--rotate` is passed, and the cluster's own copy of the secret survives the restart regardless. A stale credential in the store is a reason to re-run the seed script, not to debug the controller.

To look at what was seeded:

```bash
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=dev-token
vault kv get secret/agents-infra/local/database
```

That administrative token is a public development placeholder baked into the image, so it is used only for seeding. The cluster receives a separate periodic token whose policy can read this project's prefix and nothing else, which is what makes the credential worth having in a store at all.

## Validating a change

The scripts are the testbed, so validation means running them:

```bash
sh scripts/status.sh                          # expect: absent
sh scripts/up.sh                              # expect: three nodes Ready at 1.36.4
sh scripts/status.sh                          # expect: present, 3 nodes, server 1.36.4
kubectl --context kind-agents-infra-local get --raw /healthz   # expect: ok
sh scripts/up.sh                              # expect: already present, no second cluster
sh scripts/down.sh                            # expect: removed
sh scripts/down.sh                            # expect: nothing to delete
git -C .. status --porcelain                  # expect: no cluster state committed
```

A cluster that is created but never becomes Ready is almost always a kind version older than the pinned node image requires; the version check at the start of `up.sh` exists to catch exactly that.

## Generated files

`scripts/up.sh` writes the rendered kind configuration and the remembered kubectl context into `.generated/`, which is ignored by version control. The profile stays the single source of truth, and the rendered file is there to read when something looks wrong.

## How this differs from the managed service

The differences are deliberate and worth remembering when a chart behaves differently in Azure:

| Area | Here | In AKS |
| --- | --- | --- |
| Storage | One read-write-once host path class, no expansion, no snapshots | Managed disk and file classes, expansion and snapshots |
| Ingress | A separately installed controller, including a second installation that answers to the AKS class name | The application routing add-on |
| Transport-layer routing | Requires experimental API channel and an explicit feature flag | Not provided by application routing |
| Load balancing | Node ports published to the host | A real load balancer with an address |
| Identity | A static token in a secret | Workload identity |

## Next

Ingress, storage, metrics, secret delivery and the database chart arrive in their own tickets under `../.scratch/k8s-initial-setup/issues/`. This directory currently provides the cluster itself and nothing installed on top of it.
