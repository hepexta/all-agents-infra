#!/bin/sh
# Bring up the local cluster for a profile.
#
# Safe to run repeatedly: an existing cluster is reported rather than replaced.
#
# Usage: sh scripts/up.sh [profile] [--render-only]
#        default profile: local
#        --render-only writes and prints the kind configuration, then stops
#          before touching the container runtime. Useful for reviewing what a
#          profile actually produces.
set -eu
. "$(dirname -- "$0")/lib.sh"

RENDER_ONLY=0
PROFILE_ARG=local
for _arg in "$@"; do
	case "$_arg" in
		--render-only) RENDER_ONLY=1 ;;
		-*) die "unknown option '$_arg'" ;;
		*) PROFILE_ARG=$_arg ;;
	esac
done

load_profile "$PROFILE_ARG"
mkdir -p "$GENERATED_DIR"

# Turn the profile inputs into the kind configuration. Generated rather than
# committed so that the profile stays the single source of truth for the
# cluster name, the node count, the pinned image and the published ports.
render_config() {
	{
		printf 'kind: Cluster\n'
		printf 'apiVersion: kind.x-k8s.io/v1alpha4\n'
		printf 'name: %s\n' "$CLUSTER_NAME"
		printf 'nodes:\n'
		printf '  - role: control-plane\n'
		printf '    image: %s\n' "$NODE_IMAGE"
		if [ -n "$HOST_PORTS" ]; then
			printf '    extraPortMappings:\n'
			for _pair in $HOST_PORTS; do
				_host=${_pair%%:*}
				_node=${_pair##*:}
				case "$_host$_node" in
					''|*[!0-9]*) die "HOST_PORTS entry '$_pair' must look like host:node" ;;
				esac
				if [ "$_node" -lt 30000 ] || [ "$_node" -gt 32767 ]; then
					die "HOST_PORTS entry '$_pair': the container port is the node port and must be in 30000-32767, so host port $_host cannot map to $_node"
				fi
				printf '      - containerPort: %s\n' "$_node"
				printf '        hostPort: %s\n' "$_host"
				printf '        listenAddress: %s\n' "$LISTEN_ADDRESS"
				printf '        protocol: TCP\n'
			done
		fi
		_i=1
		while [ "$_i" -le "$WORKER_NODES" ]; do
			printf '  - role: worker\n'
			printf '    image: %s\n' "$NODE_IMAGE"
			_i=$((_i + 1))
		done
	} > "$CONFIG_FILE"
}

log "rendering the kind configuration for profile '$PROFILE'"
render_config
log "wrote $CONFIG_FILE"

if [ "$RENDER_ONLY" = "1" ]; then
	cat "$CONFIG_FILE"
	exit 0
fi

require_docker
require_kind

if cluster_present; then
	log "cluster '$CLUSTER_NAME' is already present, nothing to create"
else
	# Creating a cluster makes it the current kubectl context. Remember what it
	# was so the developer's default is not changed behind their back.
	if _previous=$(kubectl config current-context 2>/dev/null); then
		printf '%s\n' "$_previous" > "$PREVIOUS_CONTEXT_FILE"
		_restore=1
		log "current kubectl context before creation: $_previous"
	else
		_restore=0
	fi

	log "creating cluster '$CLUSTER_NAME' (Kubernetes $KUBERNETES_VERSION, 1 control plane, $WORKER_NODES worker(s))"
	kind create cluster --config "$(windows_path "$CONFIG_FILE")"

	if [ "$_restore" = "1" ]; then
		if kubectl config use-context "$_previous" >/dev/null 2>&1; then
			log "restored the current kubectl context to $_previous"
		else
			warn "could not restore the previous kubectl context ($_previous); it is still in the kubeconfig"
		fi
	fi
fi

log "waiting for every node to report Ready"
kubectl --context "$CONTEXT" wait --for=condition=Ready nodes --all --timeout=240s

log "cluster is ready"
kubectl --context "$CONTEXT" get nodes -o wide
printf '\n'
log "context: $CONTEXT"
log "inspect with: kubectl --context $CONTEXT get pods -A"
log "or make it current with: kubectl config use-context $CONTEXT"
