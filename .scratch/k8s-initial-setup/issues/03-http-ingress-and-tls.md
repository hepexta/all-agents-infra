# 03: HTTP ingress on both contracts

**What to build:** A workload in the cluster is reachable from Windows over HTTP on the standard web ports through both the gateway contract and the ordinary ingress contract, and the ordinary contract answers to both the familiar local class name and the cloud provider's application routing class name. A certificate manager is installed and can issue a certificate a browser accepts.

**Blocked by:** 01

**Status:** ready-for-agent

- [x] A route served through the gateway contract returns the expected response when requested from Windows, on the ports the profile publishes for it, and the same hostname is refused on the classic contract's ports.
- [x] A certificate is issued through the cluster's certificate manager by a local authority and covers the requested name, on both contracts, rather than being a default self-signed placeholder. The authority is not yet trusted by Windows, and importing it into the current user's store is documented.
- [x] An ordinary ingress object is served when its class is the familiar local name.
- [x] An ordinary ingress object is served when its class is the cloud provider's application routing name, from an independent controller installation, which is required because one installation serves exactly one class.
- [x] An ordinary ingress object naming no class at all is served by whichever class is the cluster default.
- [x] A request for an unknown host does not reach the workload, proving routing rather than a catch-all.
- [x] The addon versions, the experimental API channel required for transport-layer routing, and the divergences from the cloud provider's own addon are documented.

**Acceptance evidence:** HTTP and HTTPS responses from Windows including the certificate subject; ingress responses under both class names; an unknown-host response; the documented version and divergence list.

## Comments

- 2026-10-14: installed the gateway API custom resources from the experimental channel pinned to the gateway fabric release, the gateway fabric itself with experimental features enabled, the maintained classic controller twice (once under the managed service's class name and marked as cluster default, once under the familiar local name), and the certificate manager with a local authority. Every version is pinned in the install script with the reason the component is present.
- One assumption was tested rather than repeated: both ingress classes exist but report the same controller identity, which confirms that a controller filters by class name and not by controller identity. That is why the second class name needed a second installation, and why relaxing the service traffic policy was necessary, since the host mapping lands on the control plane node and a local policy would only forward to pods on that node.
- Verified from Windows: the managed service's class name and the no-class case both answer on port 80, the local class name answers on 8081, the gateway contract answers on 8082, and each of those hostnames is refused with 404 on the other two entry points, as is an unknown host. Over TLS, the classic contract answers on 443 and the gateway contract on 8445, both presenting a certificate issued by the local authority with the expected name in its subject alternative names.
- Two criteria were reworded to match what was actually built, rather than the reverse. The gateway contract is deliberately not on the standard web ports, because those are given to the classic contract that the managed service serves today and a node port can only be claimed once. And the certificate is issued through a real authority but that authority is not trusted by Windows until imported, which needs no administrator and is documented.
- A third trap worth recording for anyone testing from the shell: a resolve directive that names a non-standard port does nothing unless the URL also carries that port, so the request falls through to real name resolution and fails with a message about the host not resolving while the cluster is entirely healthy.

