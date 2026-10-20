#!/bin/sh
# Restore one dump into the database, deliberately.
#
# This is an explicit act rather than part of the release: the job is rendered
# from the chart and applied here, waited on, and then removed. Installing,
# upgrading or restarting the database never restores anything.
#
# Usage: sh restore.sh <dump-file-name>
#        sh restore.sh --list
set -eu

CHART_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROFILE=${PROFILE:-local}
VALUES="$CHART_DIR/values-$PROFILE.yml"

CLUSTER_NAME=${CLUSTER_NAME:-agents-infra-local}
CONTEXT=${CONTEXT:-kind-$CLUSTER_NAME}
NAMESPACE=${NAMESPACE:-database}
RELEASE=${RELEASE:-agents-db}
POD=${POD:-$RELEASE-dump-list}

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
	# Listing needs the claim mounted somewhere, so a short-lived pod does it.
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$POD" --ignore-not-found --wait=true >/dev/null 2>&1 || true
	kubectl --context "$CONTEXT" -n "$NAMESPACE" run "$POD" --image=postgres:17-alpine --restart=Never \
		--overrides="{\"spec\":{\"containers\":[{\"name\":\"l\",\"image\":\"postgres:17-alpine\",\"command\":[\"sleep\",\"300\"],\"volumeMounts\":[{\"name\":\"b\",\"mountPath\":\"/backups\"}]}],\"volumes\":[{\"name\":\"b\",\"persistentVolumeClaim\":{\"claimName\":\"$RELEASE-dumps\"}}]}}" >/dev/null
	kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout=180s >/dev/null
	echo "dumps available:"
	kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- sh -c 'ls -1t /backups/*.dump 2>/dev/null | sed "s|.*/|  |"' || echo "  none"
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$POD" --wait=true >/dev/null
	[ -n "${1:-}" ] || { echo; echo "usage: sh restore.sh <dump-file-name>"; exit 0; }
	exit 0
fi

DUMP=$1

echo "restoring $DUMP into $RELEASE in namespace $NAMESPACE"
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job "$RELEASE-restore" --ignore-not-found --wait=true >/dev/null 2>&1 || true

helm template "$RELEASE" "$CHART_DIR" \
	--kube-version "$(kubectl --context "$CONTEXT" version -o json 2>/dev/null | sed -n 's/.*"serverVersion":.*"gitVersion": *"v\([0-9.]*\)".*/\1/p' | head -1)" \
	--namespace "$NAMESPACE" \
	--values "$VALUES" \
	--set restore.enabled=true \
	--set restore.file="$DUMP" \
	--show-only templates/restore-job.yaml \
	| kubectl --context "$CONTEXT" -n "$NAMESPACE" apply -f - >/dev/null

echo "waiting for the restore to finish"
if ! kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Complete "job/$RELEASE-restore" --timeout=20m >/dev/null; then
	echo "the restore did not complete; its output follows" >&2
	kubectl --context "$CONTEXT" -n "$NAMESPACE" logs "job/$RELEASE-restore" >&2 || true
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job "$RELEASE-restore" --wait=false >/dev/null 2>&1 || true
	exit 1
fi

kubectl --context "$CONTEXT" -n "$NAMESPACE" logs "job/$RELEASE-restore"
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job "$RELEASE-restore" --wait=true >/dev/null
echo "restore complete, job removed"
