#!/bin/sh
# Initialise a fresh database with the platform schema, without the application
# running.
#
# The schema definition is not copied into this chart. A configuration object is
# created from the single existing definition in the parent directory and
# mounted into a short-lived job, so the repository keeps one copy of the schema
# rather than two that can drift apart.
#
# Like the restore, this is an explicit act: it is applied here, waited on, and
# removed, and it never runs as part of an install or an upgrade.
#
# Usage: sh init-schema.sh
set -eu

CHART_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_SCHEMA="$CHART_DIR/../schema.sql"
PROFILE=${PROFILE:-local}
VALUES="$CHART_DIR/values-$PROFILE.yml"

CLUSTER_NAME=${CLUSTER_NAME:-agents-infra-local}
CONTEXT=${CONTEXT:-kind-$CLUSTER_NAME}
NAMESPACE=${NAMESPACE:-database}
RELEASE=${RELEASE:-agents-db}
CONFIGMAP=${CONFIGMAP:-$RELEASE-schema}

if [ ! -f "$REPO_SCHEMA" ]; then
	echo "no schema definition at $REPO_SCHEMA" >&2
	exit 1
fi

# The configuration object is named after the file it holds, and is created
# fresh each run so it follows the definition rather than drifting from it.
SCHEMA_WIN=$(CDPATH= cd -- "$(dirname -- "$REPO_SCHEMA")" && pwd -W)/$(basename "$REPO_SCHEMA")
echo "using the schema definition at $REPO_SCHEMA"
kubectl --context "$CONTEXT" -n "$NAMESPACE" create configmap "$CONFIGMAP" \
	--from-file=schema.sql="$SCHEMA_WIN" \
	--dry-run=client -o yaml \
	| kubectl --context "$CONTEXT" -n "$NAMESPACE" apply -f - >/dev/null

SERVER_VERSION=$(kubectl --context "$CONTEXT" version -o json 2>/dev/null | sed -n 's/.*"serverVersion":.*"gitVersion": *"v\([0-9.]*\)".*/\1/p' | head -1)
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job "$RELEASE-schema" --ignore-not-found --wait=true >/dev/null 2>&1 || true

helm template "$RELEASE" "$CHART_DIR" \
	--kube-version "${SERVER_VERSION:-1.36.0}" \
	--namespace "$NAMESPACE" \
	--values "$VALUES" \
	--set schema.enabled=true \
	--set schema.configMap="$CONFIGMAP" \
	--show-only templates/schema-job.yaml \
	| kubectl --context "$CONTEXT" -n "$NAMESPACE" apply -f - >/dev/null

echo "waiting for the schema to be applied"
if ! kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Complete "job/$RELEASE-schema" --timeout=10m >/dev/null; then
	echo "the schema job did not complete; its output follows" >&2
	kubectl --context "$CONTEXT" -n "$NAMESPACE" logs "job/$RELEASE-schema" >&2 || true
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job "$RELEASE-schema" --wait=false >/dev/null 2>&1 || true
	exit 1
fi

kubectl --context "$CONTEXT" -n "$NAMESPACE" logs "job/$RELEASE-schema" | tail -5
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job "$RELEASE-schema" --wait=true >/dev/null
echo "schema applied, job removed"
