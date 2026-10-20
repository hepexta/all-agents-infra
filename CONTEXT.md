# all-agents infra

Packaging for the platform's backing services: two stacks that run as containers on a laptop, and a local Kubernetes cluster with a Helm chart that predicts how the platform's charts will behave on the managed service.

## Language

**Stack**:
A service that runs as containers under Compose, with its own directory and its own compose file.
_Avoid_: service, container, app

**Chart**:
The Helm package for one stack. The Kubernetes counterpart of a stack, sharing its contracts rather than its files.
_Avoid_: manifest, deployment, helm file

**Profile**:
A named way of building the local cluster: its name, node count, Kubernetes version and published ports, in one file.
_Avoid_: environment, config, setup

**Environment**:
The target a chart is configured for, one of local, development or production. Each has an overlay.
_Avoid_: profile, stage, tier

**Overlay**:
A values file that adds to or replaces a chart's defaults for one environment.
_Avoid_: override, delta, patch

**Contract**:
A set of names or file conventions that two sides depend on, such as the connection variable names or the dump file naming. Changing one side without the other is a bug.
_Avoid_: interface, API, convention

**Dump**:
A database export in custom format, named by the moment it was taken. The stack and the cluster produce interchangeable dumps.
_Avoid_: backup, snapshot, export

**Sentinel**:
The file whose presence means a restore is under way, so that no dump captures a half-restored database.
_Avoid_: lock, flag, marker

**Publication**:
Making the database reachable from outside the cluster through a transport-layer listener, rather than through an ingress.
_Avoid_: exposure, ingress, port forward

**Parity**:
The property of the local cluster behaving like the managed service for everything a chart depends on. Where that is impossible the difference is written down, not simulated.
_Avoid_: compatibility, fidelity, emulation

**Managed service**:
The cloud Kubernetes environment the charts are eventually deployed to. Named generically because nothing here depends on which one it is.
_Avoid_: AKS, cloud, production
