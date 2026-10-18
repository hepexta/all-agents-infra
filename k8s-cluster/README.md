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
| 80 | 30080 | Classic Ingress under the managed service's class name, and the cluster default |
| 443 | 30443 | The same, for TLS |
| 8081 | 30081 | Classic Ingress under the familiar local class name |
| 8444 | 30444 | The same, for TLS |
| 8082 | 30082 | Gateway API |
| 8445 | 30445 | The same, for TLS |
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

## Addons

```bash
sh scripts/addons-up.sh           # install or upgrade the pinned addons (idempotent)
```

Every chart version is pinned in the script with the reason the addon exists, so a run months from now produces the same cluster and a reader can see what each piece stands in for.

| Addon | Version | Why it is here |
| --- | --- | --- |
| metrics-server | chart 3.14.0 | The managed cluster reports usage by default; this lets resource requests in a chart be checked against real numbers |
| gateway API custom resources | experimental channel at v2.7.2 | Transport-layer routing only exists in that channel, and it is the revision the gateway fabric was built against |
| NGINX Gateway Fabric | chart 2.7.2 | The gateway contract, and the transport-layer routing the database will need |
| NGINX Ingress Controller | chart 2.7.3, installed twice | The classic contract, under both the managed service's class name and the familiar local one. Upstream ingress-nginx is archived and receives no further fixes |
| cert-manager | chart 1.21.2 | Certificates issued through a real issuer chain, so a chart that expects certificates can be tested |

Usage reporting needs one relaxation that must not travel: kind signs the kubelet certificates with the cluster's own CA, which metrics-server does not trust, so it reports nothing at all until verification is disabled. That lives in `addons/metrics-server/values.yaml` and is acceptable only because this cluster is a throwaway bound to the loopback interface.

```bash
kubectl --context kind-agents-infra-local top nodes
```

## Storage

The class is the one kind bundles, named `standard`, and it **is** the default, so a claim naming no class binds through it.

Two limitations matter when testing a chart, and both differ from the managed service:

- **Read-write-once only.** The volume is a directory on whichever node used it first, and the volume carries a node affinity that pulls later pods back to that node. A chart needing a shared read-write-many volume cannot be validated here.
- **No expansion and no snapshots.** Growing a claim after the fact, and taking a volume snapshot, both fail, so a chart depending on either needs a different local approach.

Verify with the committed check, which claims without naming a class, writes a marker, replaces the pod, and reads the marker back from the new pod:

```bash
CTX=kind-agents-infra-local
kubectl --context $CTX apply -f tests/storage-check.yaml
kubectl --context $CTX wait --for=condition=Ready pod/storage-check-writer --timeout=180s
MSYS_NO_PATHCONV=1 kubectl --context $CTX exec storage-check-writer -- cat /data/marker
kubectl --context $CTX delete pod storage-check-writer --wait=true
kubectl --context $CTX apply -f tests/storage-check-reader.yaml
kubectl --context $CTX wait --for=condition=Ready pod/storage-check-reader --timeout=180s
MSYS_NO_PATHCONV=1 kubectl --context $CTX exec storage-check-reader -- cat /data/marker
kubectl --context $CTX delete pod storage-check-reader --ignore-not-found
kubectl --context $CTX delete -f tests/storage-check.yaml
```

The `MSYS_NO_PATHCONV=1` is required on every command whose argument is a path inside a container. Without it the shell rewrites `/data/marker` into a Windows path, and the command fails complaining about a directory that does not exist on the host. That failure looks exactly like a broken volume, and is not one.

## Ingress

Two contracts are served at once, because charts written today use the first and the managed service is moving to the second.

| Contract | Class | Host ports | Served by |
| --- | --- | --- | --- |
| Classic Ingress | `webapprouting.kubernetes.azure.com`, also the cluster default | 80, 443 | one controller installation |
| Classic Ingress | `nginx` | 8081, 8444 | a second installation of the same chart |
| Gateway API | GatewayClass `nginx` | 8082, 8445 | NGINX Gateway Fabric |

Three things about this arrangement are deliberate.

**The standard ports belong to the classic contract.** That is the contract the managed service's application routing add-on serves, so a chart written for it works on the addresses people already type. Gateway API is on its own ports because a node port can be claimed by exactly one service, so two controllers cannot share 80.

**The AKS class name costs a whole extra installation.** A controller handles exactly one Ingress class, so mirroring that name is a second release rather than a second class on the first. That installation is marked as the cluster default, so an Ingress naming no class at all is also served, which is what makes a chart with no `ingressClassName` work.

**Transport-layer routing needs the experimental channel.** The gateway's ability to publish a plain TCP service, which the database needs, is only available from the experimental custom resources with a feature flag switched on. That is installed and enabled; it is also something the managed service would not install, so a chart must not come to depend on it.

Validate with the committed check, which deploys one small workload behind four routes:

```bash
CTX=kind-agents-infra-local
kubectl --context $CTX apply -f tests/ingress-check.yaml
kubectl --context $CTX -n default rollout status deploy/ingress-check --timeout=180s
# the managed service's class name, on the standard port
curl -s -H 'Host: aks-class.local' http://127.0.0.1:80/
# no class named at all: the default picks it up
curl -s -H 'Host: default-class.local' http://127.0.0.1:80/
# the familiar local class name, through the second installation
curl -s -H 'Host: nginx-class.local' http://127.0.0.1:8081/
# the gateway contract
curl -s -H 'Host: gateway-class.local' http://127.0.0.1:8082/
# each hostname on the wrong controller must not be served
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: nginx-class.local' http://127.0.0.1:80/    # expect 404
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: aks-class.local' http://127.0.0.1:8081/    # expect 404
```

Certificates come from a local authority created along with cert-manager, requested declaratively by an annotation on the Ingress. These succeed:

```bash
curl -sk --resolve tls-check.local:443:127.0.0.1 https://tls-check.local/          # classic
curl -sk --resolve gateway-class.local:8445:127.0.0.1 https://gateway-class.local:8445/   # gateway
```

Note the port in the second URL. Without it `--resolve` never matches and curl falls through to real DNS, which fails with a message about the host not resolving even though everything is healthy.

Windows does not trust the local authority, so a browser will warn until it is imported. Adding it to the **current user's** store needs no administrator:

```bash
kubectl --context $CTX -n cert-manager get secret local-ca-secret -o jsonpath='{.data.tls\.crt}' | base64 -d > local-ca.crt
certutil -addstore -user Root local-ca.crt     # from PowerShell or cmd
```

### Publishing a plain TCP service to the host

The gateway carries a transport-layer listener on 5432, wired to node port 30433 and published as host port **15433**. The database chart attaches its own route to that listener, so until it does, the listener exists with nothing behind it.

The rule that shapes this: the container port in the profile **is** the node port, so the two numbers have to agree and the node port has to sit inside the node port range. That is why the database cannot appear on the host port the container stack already owns, and turns up on 15433 instead.

One trap deserves stating plainly, because it makes a broken setup look healthy: **a published port accepts a connection even when nothing is behind it.** The mapping forwards to the node before any service is involved, so a socket that opens proves nothing whatsoever. The shortest demonstration:

```bash
# succeeds, with no route attached to the listener at all
(exec 3<>/dev/tcp/127.0.0.1/15433) && echo connected
```

Every reachability check in this repository therefore asserts on a payload, a query returning a known row, rather than on a connection that opens.

Validate the path with the committed check, which attaches a throwaway database to the listener:

```bash
CTX=kind-agents-infra-local
kubectl --context $CTX apply -f tests/tcp-publish-check.yaml
kubectl --context $CTX -n default rollout status deploy/tcp-check-db --timeout=240s
# over the published host port, using the client inside the existing container stack
docker exec -e PGPASSWORD=tcpcheck-only agents-db psql -h host.docker.internal -p 15433 -U tcpcheck -d tcpcheck \
  -c "select 'reached the cluster over the published port'"
# the same instance, from inside the cluster
kubectl --context $CTX -n default exec deploy/tcp-check-db -- env PGPASSWORD=tcpcheck-only \
  psql -U tcpcheck -d tcpcheck -h tcp-check-db -tAc "select 'and the same instance from inside'"
kubectl --context $CTX -n default delete -f tests/tcp-publish-check.yaml
```

No database client is installed on Windows, so the client above is the one inside the existing container stack. That works because a container on this machine can reach a host port bound to the loopback address, which is worth knowing before concluding that a loopback binding blocks everything outside.

### Delivery into the cluster

Credentials are never copied by hand. A cluster-scoped store points at the local secret store, an external secret in the `database` namespace derives a Kubernetes secret named `agents-db-credentials`, and the database chart consumes that secret by name. Nothing else in the repository holds the credential, and the derived secret is owned by its external secret, so it cannot drift.

```bash
kubectl --context kind-agents-infra-local get clustersecretstore vault-local
kubectl --context kind-agents-infra-local -n database get externalsecret agents-db-credentials
kubectl --context kind-agents-infra-local -n database get secret agents-db-credentials
```

The cluster authenticates with the scoped token, never the administrative one. Checked from inside a pod holding that token: its own path answers, and a path outside this project's prefix is refused. On a managed cluster the same shape fronts the cloud secret manager with workload identity, and this token disappears entirely.

Three things are worth knowing, each of which cost time to find:

- **The token must not keep its trailing newline.** The seed script writes an ordinary text file, which ends with one, and handing that file over verbatim puts the newline inside the credential. The controller then reports the store as containing non-printable characters, which reads like a bad credential rather than a stray byte. The install script trims it as it builds the secret.
- **The controller revalidates the store on a backoff.** Once a store has been invalid, the next attempt can be minutes away even though the fix is already in place, so a wait that expires is not evidence that the fix failed.
- **A pod reaches the host store directly.** A container on this machine resolves the host alias and can reach a port bound to the loopback address, which is why no network bridging or hand-written endpoint is needed.

## Validating a change

The scripts are the testbed, so validation means running them:

```bash
sh scripts/status.sh                          # expect: absent
sh scripts/up.sh                              # expect: three nodes Ready at 1.36.4
sh scripts/status.sh                          # expect: present, 3 nodes, server 1.36.4
MSYS_NO_PATHCONV=1 kubectl --context kind-agents-infra-local get --raw /healthz   # expect: ok
sh scripts/up.sh                              # expect: already present, no second cluster
sh scripts/down.sh                            # expect: removed
sh scripts/down.sh                            # expect: nothing to delete
git -C .. status --porcelain                  # expect: no cluster state committed
```

The `MSYS_NO_PATHCONV=1` on the health check is not decoration. Git Bash rewrites any argument that looks like a Unix path before a Windows binary sees it, so `/healthz` arrives at kubectl as something like `C:/Program Files/Git/healthz` and the API server answers `NotFound`. The same trap is described in the repository's convention document for container-internal paths, and it applies to every raw API path passed to a Windows client.

A cluster that is created but never becomes Ready is almost always a kind version older than the pinned node image requires; the version check at the start of `up.sh` exists to catch exactly that.

## Generated files

`scripts/up.sh` writes the rendered kind configuration and the remembered kubectl context into `.generated/`, which is ignored by version control. The profile stays the single source of truth, and the rendered file is there to read when something looks wrong.

## How this differs from the managed service

The differences are deliberate and worth remembering when a chart behaves differently in Azure:

| Area | Here | In AKS |
| --- | --- | --- |
| Storage | One read-write-once host path class, no expansion, no snapshots | Managed disk and file classes, expansion and snapshots |
| Ingress | Three controllers: two installations of a maintained classic controller, plus a gateway implementation | The application routing add-on, one controller under one class name |
| Transport-layer routing | Requires the experimental API channel and an explicit feature flag | Not provided by application routing |
| Certificates | cert-manager with a local authority, untrusted by Windows until imported | Key Vault certificates through the secrets store driver; no certificate manager is installed by default |
| Load balancing | Node ports published to the host | A real load balancer with an address |
| Identity | A static token in a secret | Workload identity |

## Next

Secret delivery into the cluster and the database chart arrive in their own tickets under `../.scratch/k8s-initial-setup/issues/`. This directory provides the cluster and the platform services a chart can rely on: storage, usage reporting, ingress under both contracts, and certificates.

## Hashicorp Vault
```
$ export VAULT_ADDR=http://127.0.0.1:8200
$ vault login
$ vault kv get -mount="secret" "agents-infra/local/database"
```
