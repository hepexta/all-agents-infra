#!/bin/sh
# Report the state of the local cluster for a profile. Changes nothing.
#
# Usage: sh scripts/status.sh [profile]    (default profile: local)
set -eu
. "$(dirname -- "$0")/lib.sh"

load_profile "${1:-local}"
require_docker

printf 'profile:     %s\n' "$PROFILE"
printf 'cluster:     %s\n' "$CLUSTER_NAME"
printf 'context:     %s\n' "$CONTEXT"
printf 'kubernetes:  %s\n' "$KUBERNETES_VERSION"

if ! cluster_present; then
	printf 'state:       absent\n'
	exit 0
fi

printf 'state:       present\n'

if _nodes=$(kubectl --context "$CONTEXT" get nodes --no-headers 2>/dev/null); then
	printf 'nodes:       %s\n' "$(printf '%s\n' "$_nodes" | grep -c .)"
	printf '%s\n' "$_nodes" | awk '{ printf "  %-34s %-10s %s\n", $1, $2, $5 }'
	_server=$(kubectl --context "$CONTEXT" version 2>/dev/null | sed -n 's/^Server Version: *//p')
	[ -n "$_server" ] && printf 'server:      %s\n' "$_server"
else
	warn "the cluster is registered but its API server did not answer"
fi
