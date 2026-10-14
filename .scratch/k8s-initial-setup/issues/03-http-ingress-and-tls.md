# 03: HTTP ingress on both contracts

**What to build:** A workload in the cluster is reachable from Windows over HTTP on the standard web ports through both the gateway contract and the ordinary ingress contract, and the ordinary contract answers to both the familiar local class name and the cloud provider's application routing class name. A certificate manager is installed and can issue a certificate a browser accepts.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] A route served through the gateway contract returns the expected response when requested from Windows on the standard HTTP port.
- [ ] The same holds on the standard HTTPS port once a certificate has been issued, and the served certificate is not an unknown-authority placeholder.
- [ ] An ordinary ingress object is served when its class is the familiar local name.
- [ ] An ordinary ingress object is served when its class is the cloud provider's application routing name, from an independent controller installation, which is required because one installation serves exactly one class.
- [ ] A request for an unknown host does not reach the workload, proving routing rather than a catch-all.
- [ ] The addon versions, the experimental API channel required for transport-layer routing, and the divergences from the cloud provider's own addon are documented.

**Acceptance evidence:** HTTP and HTTPS responses from Windows including the certificate subject; ingress responses under both class names; an unknown-host response; the documented version and divergence list.
