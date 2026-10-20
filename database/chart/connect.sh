#!/bin/sh
# Print the settings the application needs to reach one of the two databases,
# so that switching between them is a copy rather than a guess.
#
# Nothing here writes into the application's repository. The values are printed
# for whatever runs the application to consume, which keeps this repository from
# reaching outside itself and keeps the application's own environment file its
# own business.
#
# Usage: sh connect.sh [forward|published|compose]
#
#   forward    the cluster database through a port-forward on the reserved port
#   published  the cluster database on the port the cluster publishes
#   compose    the container stack's database, on its own host port
set -eu

TARGET=${1:-forward}
CLUSTER_NAME=${CLUSTER_NAME:-agents-infra-local}
CONTEXT=${CONTEXT:-kind-$CLUSTER_NAME}
NAMESPACE=${NAMESPACE:-database}
RELEASE=${RELEASE:-agents-db}

print_common() {
	printf 'POSTGRES_DB=%s\n' "${1}"
	printf 'POSTGRES_USER=%s\n' "${2}"
	printf 'POSTGRES_PASSWORD=%s\n' "${3}"
}

case "$TARGET" in
forward)
	printf 'POSTGRES_HOST=localhost\n'
	printf 'POSTGRES_PORT=15432\n'
	_password=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" \
		get secret "${RELEASE}-credentials" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
	print_common allagents agents "$_password"
	printf '# start the tunnel first: kubectl --context %s -n %s port-forward svc/%s 15432:5432\n' \
		"$CONTEXT" "$NAMESPACE" "$RELEASE"
	;;
published)
	printf 'POSTGRES_HOST=localhost\n'
	printf 'POSTGRES_PORT=15433\n'
	_password=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" \
		get secret "${RELEASE}-credentials" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
	print_common allagents agents "$_password"
	printf '# requires the chart installed with access.gatewayTcp.enabled=true\n'
	;;
compose)
	printf 'POSTGRES_HOST=localhost\n'
	printf 'POSTGRES_PORT=5432\n'
	print_common allagents agents agents
	printf '# the container stack, whose password is a documented local development default\n'
	;;
*)
	echo "unknown target '$TARGET'; expected forward, published or compose" >&2
	exit 1
	;;
esac
