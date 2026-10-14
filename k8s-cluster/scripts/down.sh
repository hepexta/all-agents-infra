#!/bin/sh
# Remove the local cluster for a profile.
#
# Safe to run when the cluster is already gone.
#
# Usage: sh scripts/down.sh [profile]      (default profile: local)
set -eu
. "$(dirname -- "$0")/lib.sh"

load_profile "${1:-local}"
require_docker

if ! cluster_present; then
	log "cluster '$CLUSTER_NAME' is not present, nothing to delete"
	exit 0
fi

log "deleting cluster '$CLUSTER_NAME'"
kind delete cluster --name "$CLUSTER_NAME"

# Deleting a cluster removes its context. If that context was current, put the
# developer back on whatever they were using before this cluster existed.
_current=$(kubectl config current-context 2>/dev/null || true)
if [ -z "$_current" ] || [ "$_current" = "$CONTEXT" ]; then
	if [ -f "$PREVIOUS_CONTEXT_FILE" ]; then
		_previous=$(cat "$PREVIOUS_CONTEXT_FILE")
		if [ -n "$_previous" ] && kubectl config use-context "$_previous" >/dev/null 2>&1; then
			log "restored the current kubectl context to $_previous"
		fi
	fi
fi

log "cluster '$CLUSTER_NAME' removed"
