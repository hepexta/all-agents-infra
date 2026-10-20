#!/bin/sh
# Copy the newest dump out of the cluster into the repository's backup folder,
# so that backups stay plain files that can be opened, copied and archived
# without going through the cluster.
#
# The folder is ignored by version control for dump files, as it is for the
# container stack, so nothing here ends up committed.
#
# Usage: sh fetch-dump.sh [destination-directory]
set -eu

CHART_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$CHART_DIR/../.." && pwd)
DEST=${1:-$REPO_ROOT/database/bck}

CLUSTER_NAME=${CLUSTER_NAME:-agents-infra-local}
CONTEXT=${CONTEXT:-kind-$CLUSTER_NAME}
NAMESPACE=${NAMESPACE:-database}
RELEASE=${RELEASE:-agents-db}
CLAIM=${CLAIM:-$RELEASE-dumps}
POD=${POD:-$RELEASE-dump-fetch}
IMAGE=${IMAGE:-postgres:17-alpine}

mkdir -p "$DEST"

# A pod that simply stays up with the dumps claim attached, so that the newest
# file can be listed and then copied out of it. It is removed again below.
cleanup() {
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$POD" --ignore-not-found --wait=true >/dev/null 2>&1 || true

kubectl --context "$CONTEXT" -n "$NAMESPACE" run "$POD" \
	--image="$IMAGE" --restart=Never \
	--overrides="{\"spec\":{\"containers\":[{\"name\":\"fetch\",\"image\":\"$IMAGE\",\"command\":[\"sleep\",\"600\"],\"volumeMounts\":[{\"name\":\"backups\",\"mountPath\":\"/backups\"}]}],\"volumes\":[{\"name\":\"backups\",\"persistentVolumeClaim\":{\"claimName\":\"$CLAIM\"}}]}}" \
	>/dev/null

kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout=180s >/dev/null

NEWEST=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- sh -c 'ls -1t /backups/*.dump 2>/dev/null | head -1' | tr -d '\r')
if [ -z "$NEWEST" ]; then
	echo "no dump found on the claim; has the dump job run yet?" >&2
	exit 1
fi

echo "newest dump in the cluster: $(basename "$NEWEST")"

# Three path problems meet in this one call on Windows. The shell rewrites the
# container path so that it no longer looks remote; the local side then has to
# be a Windows path; and a Windows path contains a colon, which the copy command
# reads as the separator before a pod name, making the destination look remote
# as well. So the rewriting is suppressed and the copy runs from inside the
# destination directory, where a bare relative name has no colon to confuse it.
(
	cd "$DEST" || exit 1
	MSYS_NO_PATHCONV=1 kubectl --context "$CONTEXT" -n "$NAMESPACE" cp \
		"$POD:$NEWEST" "./$(basename "$NEWEST")"
)

cleanup
trap - EXIT INT TERM

ls -l "$DEST/$(basename "$NEWEST")"
echo "copied to $DEST"
