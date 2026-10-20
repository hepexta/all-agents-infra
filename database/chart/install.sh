#!/bin/sh
# Install or upgrade the database chart into the local cluster.
#
# Safe to run repeatedly: it is a helm upgrade with --install, so an existing
# release is updated in place rather than duplicated.
#
# Usage: sh install.sh [local|dev|prod]        (default: local)
set -eu

CHART_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROFILE=${1:-local}
VALUES="$CHART_DIR/values-$PROFILE.yml"

[ -f "$VALUES" ] || { echo "no values file for environment '$PROFILE' (looked for $VALUES)" >&2; exit 1; }

CLUSTER_NAME=${CLUSTER_NAME:-agents-infra-local}
CONTEXT=${CONTEXT:-kind-$CLUSTER_NAME}
NAMESPACE=${NAMESPACE:-database}
RELEASE=${RELEASE:-agents-db}

# Paths are left alone here on purpose: the shell converts them for the Windows
# helm binary, and suppressing that would hand it a path it cannot read.
echo "installing $RELEASE from $CHART_DIR with $VALUES"
exec helm upgrade --install "$RELEASE" "$CHART_DIR" \
	--kube-context "$CONTEXT" \
	--namespace "$NAMESPACE" --create-namespace \
	--values "$VALUES" \
	--wait --timeout 10m
