#!/bin/sh
# The whole acceptance bar, in one command.
#
# Prints one line per check, exits non-zero if any of them failed, and leaves
# everything as it found it apart from a test row in the database and a job or
# two, which it cleans up.
#
# Nothing here asserts on the existence of an object where it could assert on
# behaviour instead, and every reachability check carries a real payload: a
# published port accepts a connection with nothing behind it, so a socket that
# opens proves nothing.
#
# Usage: sh scripts/smoke-test.sh [profile]        (default profile: local)
set -eu
. "$(dirname -- "$0")/lib.sh"

load_profile "${1:-local}"
require_docker

PASSED=0
FAILED=0
SKIPPED=0
ok()   { PASSED=$((PASSED + 1)); printf '  PASS     %s\n' "$*"; }
bad()  { FAILED=$((FAILED + 1)); printf '  FAIL     %s\n' "$*"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  SKIP     %s\n' "$*"; }
section() { printf '\n%s\n' "$*"; }

REPO_ROOT=$(CDPATH= cd -- "$CLUSTER_ROOT/.." && pwd)
CHART_DIR="$REPO_ROOT/database/chart"
NAMESPACE=${NAMESPACE:-database}
RELEASE=${RELEASE:-agents-db}
PORT_FORWARD=15432
PORT_PUBLISHED=15433

section "cluster"
if cluster_present; then
	ok "cluster $CLUSTER_NAME exists"
	_nodes=$(kubectl --context "$CONTEXT" get nodes --no-headers 2>/dev/null || true)
	if [ "$(printf '%s\n' "$_nodes" | grep -c ' Ready ')" -eq 3 ]; then
		ok "all three nodes are Ready"
	else
		bad "expected three Ready nodes, found $(printf '%s\n' "$_nodes" | grep -c ' Ready ' || echo 0)"
	fi
	if printf '%s\n' "$_nodes" | grep -q "v$KUBERNETES_VERSION"; then
		ok "nodes run the pinned version $KUBERNETES_VERSION"
	else
		bad "nodes are not on the pinned version $KUBERNETES_VERSION"
	fi
else
	bad "cluster $CLUSTER_NAME does not exist; run 'sh scripts/up.sh $PROFILE' first"
	printf '\n%d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
	exit 1
fi

section "platform services"
if kubectl --context "$CONTEXT" top nodes 2>/dev/null | grep -q '%'; then
	ok "usage reporting answers"
else
	bad "usage reporting answers nothing"
fi

_classes=$(kubectl --context "$CONTEXT" get ingressclass --no-headers 2>/dev/null || true)
printf '%s\n' "$_classes" | grep -q '^webapprouting.kubernetes.azure.com' \
	&& ok "the managed service's ingress class is served" || bad "the managed service's ingress class is missing"
printf '%s\n' "$_classes" | grep -q '^nginx ' \
	&& ok "the familiar local ingress class is served" || bad "the familiar local ingress class is missing"
printf '%s\n' "$_classes" | grep -q 'webapprouting.kubernetes.azure.com (default)' \
	&& ok "the managed service's class is the cluster default" || bad "no default ingress class is marked"

kubectl --context "$CONTEXT" get gatewayclass nginx -o go-template='{{range .status.conditions}}{{.type}}={{.status}}{{end}}' 2>/dev/null | grep -q 'Accepted=True' \
	&& ok "the gateway class is accepted" || bad "the gateway class is not accepted"

kubectl --context "$CONTEXT" get clustersecretstore vault-local -o go-template='{{range .status.conditions}}{{.type}}={{.status}}{{end}}' 2>/dev/null | grep -q 'Ready=True' \
	&& ok "the secret store reference is valid" || bad "the secret store reference is not valid"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get externalsecret "$RELEASE-credentials" -o go-template='{{range .status.conditions}}{{.type}}={{.status}}{{end}}' 2>/dev/null | grep -q 'Ready=True' \
	&& ok "the credential is derived from the store" || bad "the credential is not derived from the store"

section "the chart"
if helm lint "$CHART_DIR" --values "$CHART_DIR/values-local.yml" >/dev/null 2>&1; then
	ok "lint is clean"
else
	bad "lint reported problems"
fi
_objects=$(helm template "$RELEASE" "$CHART_DIR" --values "$CHART_DIR/values-local.yml" 2>/dev/null | grep -c '^kind:' || echo 0)
if [ "$_objects" -ge 10 ]; then
	ok "rendering produces $_objects objects"
else
	bad "rendering produced only $_objects objects"
fi
if helm list --kube-context "$CONTEXT" -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q "^$RELEASE"; then
	ok "release $RELEASE is deployed"
else
	bad "release $RELEASE is not deployed"
fi
if kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$RELEASE-0" --timeout=60s >/dev/null 2>&1; then
	ok "the database pod is ready"
else
	bad "the database pod is not ready"
fi
if [ "$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pvc "data-$RELEASE-0" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ]; then
	ok "the data claim is bound"
else
	bad "the data claim is not bound"
fi
_security=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get statefulset "$RELEASE" -o go-template='{{range .spec.template.spec.containers}}{{.securityContext.readOnlyRootFilesystem}}/{{.securityContext.allowPrivilegeEscalation}}{{end}}' 2>/dev/null)
[ "$_security" = "true/false" ] && ok "the server runs with a read-only root filesystem and no escalation" \
	|| bad "the server's security context is not as specified ($_security)"
_uid=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get statefulset "$RELEASE" -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null)
[ "${_uid:-0}" != "0" ] && ok "the server runs as an unprivileged user (uid $_uid)" || bad "the server may run as root"

if helm test "$RELEASE" --kube-context "$CONTEXT" -n "$NAMESPACE" --timeout 3m >/dev/null 2>&1; then
	ok "the chart's own connection test passes, including refusing a wrong credential"
else
	bad "the chart's connection test failed"
fi

section "credentials"
_secret_keys=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get secret "$RELEASE-credentials" -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}' 2>/dev/null || true)
for k in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB; do
	printf '%s' "$_secret_keys" | grep -q "$k" && ok "the derived secret carries $k" || bad "the derived secret is missing $k"
done
DB_USER=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get secret "$RELEASE-credentials" -o jsonpath='{.data.POSTGRES_USER}' 2>/dev/null | base64 -d || true)
DB_NAME=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get secret "$RELEASE-credentials" -o jsonpath='{.data.POSTGRES_DB}' 2>/dev/null | base64 -d || true)
DB_PASSWORD=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get secret "$RELEASE-credentials" -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d || true)

# Prefer a client installed on the machine; fall back to the one inside the
# container stack, which is a genuine external client from the cluster's point
# of view. If neither exists the network checks are skipped rather than failed,
# because that would be a gap in the test bed, not in the platform.
client() {
	_port=$1
	_sql=$2
	if command -v psql >/dev/null 2>&1; then
		PGPASSWORD=$DB_PASSWORD psql -h 127.0.0.1 -p "$_port" -U "$DB_USER" -d "$DB_NAME" -tAc "$_sql" 2>&1
	elif docker ps --filter name=agents-db --format '{{.Names}}' 2>/dev/null | grep -qx agents-db; then
		docker exec -e PGPASSWORD="$DB_PASSWORD" agents-db psql -h host.docker.internal -p "$_port" -U "$DB_USER" -d "$DB_NAME" -tAc "$_sql" 2>&1
	else
		return 127
	fi
}

section "access from outside the cluster"
if command -v psql >/dev/null 2>&1 || docker ps --filter name=agents-db --format '{{.Names}}' 2>/dev/null | grep -qx agents-db; then
	kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward "svc/$RELEASE" "$PORT_FORWARD:5432" >/dev/null 2>&1 &
	_forward_pid=$!
	_i=0
	while [ "$_i" -lt 20 ]; do
		client "$PORT_FORWARD" "select 1" >/dev/null 2>&1 && break
		_i=$((_i + 1)); sleep 1
	done
	if client "$PORT_FORWARD" "select 'ok'" | grep -q ok; then
		ok "an authenticated session works through the port-forward on $PORT_FORWARD"
	else
		bad "no session through the port-forward on $PORT_FORWARD"
	fi
	kill "$_forward_pid" 2>/dev/null || true
	wait "$_forward_pid" 2>/dev/null || true

	if client "$PORT_PUBLISHED" "select 'ok'" 2>/dev/null | grep -q ok; then
		ok "an authenticated session works against the published port $PORT_PUBLISHED"
	else
		skip "the published port $PORT_PUBLISHED is not serving (publication may be off in this overlay)"
	fi
else
	skip "no database client available on this machine or in the container stack"
fi

section "data"
if client "$PORT_PUBLISHED" "select 1" >/dev/null 2>&1; then
	_marker="smoke-$$"
	client "$PORT_PUBLISHED" "create table if not exists smoke_test(marker text primary key, at timestamptz not null default now())" >/dev/null 2>&1 || true
	client "$PORT_PUBLISHED" "insert into smoke_test(marker) values ('$_marker') on conflict do nothing" >/dev/null 2>&1 || true
	if client "$PORT_PUBLISHED" "select count(*) from smoke_test where marker = '$_marker'" | grep -qx 1; then
		ok "a row written over the published port is readable back"
	else
		bad "a row written over the published port could not be read back"
	fi

	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$RELEASE-0" --wait=true >/dev/null 2>&1 || true
	kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$RELEASE-0" --timeout=300s >/dev/null 2>&1 || true
	_i=0
	while [ "$_i" -lt 30 ]; do
		client "$PORT_PUBLISHED" "select 1" >/dev/null 2>&1 && break
		_i=$((_i + 1)); sleep 2
	done
	if client "$PORT_PUBLISHED" "select count(*) from smoke_test where marker = '$_marker'" | grep -qx 1; then
		ok "the row survived a pod replacement, so nothing rolls back on start"
	else
		bad "the row did not survive a pod replacement"
	fi

	# An upgrade that changes the workload, so the pod is replaced by the
	# release rather than by this script, and the row has to survive that too.
	if helm upgrade "$RELEASE" "$CHART_DIR" --kube-context "$CONTEXT" -n "$NAMESPACE" \
		--values "$CHART_DIR/values-local.yml" --set postgresql.maxConnections=51 \
		--wait --timeout 10m >/dev/null 2>&1; then
		_i=0
		while [ "$_i" -lt 40 ]; do
			client "$PORT_PUBLISHED" "select 1" >/dev/null 2>&1 && break
			_i=$((_i + 1)); sleep 3
		done
		if client "$PORT_PUBLISHED" "select count(*) from smoke_test where marker = '$_marker'" | grep -qx 1; then
			ok "the row survived a chart upgrade"
		else
			bad "the row did not survive a chart upgrade"
		fi
		helm upgrade "$RELEASE" "$CHART_DIR" --kube-context "$CONTEXT" -n "$NAMESPACE" \
			--values "$CHART_DIR/values-local.yml" --wait --timeout 10m >/dev/null 2>&1 || true
	else
		bad "the release did not upgrade"
	fi
else
	skip "the data checks need a reachable database"
fi

section "dumps"
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job smoke-test-dump --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$CONTEXT" -n "$NAMESPACE" create job --from="cronjob/$RELEASE-dump" smoke-test-dump >/dev/null 2>&1 || true
if kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Complete job/smoke-test-dump --timeout=300s >/dev/null 2>&1; then
	ok "the dump job completes"
	if kubectl --context "$CONTEXT" -n "$NAMESPACE" logs job/smoke-test-dump 2>/dev/null | grep -q 'allagents-.*\.dump'; then
		ok "the dump kept the container stack's naming convention"
	else
		bad "the dump did not report a file with the expected name"
	fi

	# A dump that exists is not a dump that restores. This loads the newest one
	# into a scratch database and compares row counts, which is the observation
	# that would show the file to be truncated or unreadable.
	_restore_pod=smoke-test-restore
	_image=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get statefulset "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
	[ -n "$_image" ] || _image=postgres:17-alpine
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$_restore_pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
	kubectl --context "$CONTEXT" -n "$NAMESPACE" run "$_restore_pod" --image="$_image" --restart=Never \
		--overrides="{\"spec\":{\"containers\":[{\"name\":\"r\",\"image\":\"$_image\",\"command\":[\"sleep\",\"600\"],\"volumeMounts\":[{\"name\":\"b\",\"mountPath\":\"/backups\"}]}],\"volumes\":[{\"name\":\"b\",\"persistentVolumeClaim\":{\"claimName\":\"$RELEASE-dumps\"}}]}}" \
		>/dev/null 2>&1 || true

	if kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$_restore_pod" --timeout=180s >/dev/null 2>&1; then
		in_pod() { MSYS_NO_PATHCONV=1 kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$_restore_pod" -- sh -c "$1" 2>/dev/null; }
		_dump=$(in_pod 'ls -1t /backups/*.dump | head -1' | tr -d '\r')
		_live=$(client "$PORT_PUBLISHED" "select count(*) from smoke_test" 2>/dev/null | tr -d ' \r' || echo "")
		if [ -z "$_dump" ]; then
			bad "no dump was found on the claim to restore"
		elif [ -z "$_live" ]; then
			skip "the restore check needs a reachable database to compare against"
		else
			in_pod "PGPASSWORD=$DB_PASSWORD psql -q -h $RELEASE -U $DB_USER -d postgres -c 'DROP DATABASE IF EXISTS smoke_restore' -c 'CREATE DATABASE smoke_restore'" >/dev/null 2>&1 || true
			if in_pod "PGPASSWORD=$DB_PASSWORD pg_restore --no-owner --exit-on-error -h $RELEASE -U $DB_USER -d smoke_restore '$_dump'" >/dev/null 2>&1; then
				_restored=$(in_pod "PGPASSWORD=$DB_PASSWORD psql -tA -h $RELEASE -U $DB_USER -d smoke_restore -c 'select count(*) from smoke_test'" | tr -d ' \r')
				if [ "$_restored" = "$_live" ]; then
					ok "the newest dump restores into a scratch database with the same row count ($_restored)"
				else
					bad "the dump restored '$_restored' rows against '$_live' live"
				fi
			else
				bad "the newest dump would not restore at all"
			fi
			in_pod "PGPASSWORD=$DB_PASSWORD psql -q -h $RELEASE -U $DB_USER -d postgres -c 'DROP DATABASE IF EXISTS smoke_restore'" >/dev/null 2>&1 || true
		fi
	else
		bad "could not start a pod to check that the dump restores"
	fi
	kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$_restore_pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
else
	bad "the dump job did not complete"
fi
kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job smoke-test-dump --ignore-not-found >/dev/null 2>&1 || true

section "summary"
printf '  %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
printf '\nThe cluster is still running. To remove it:\n  sh %s/down.sh %s\n' "$CLUSTER_ROOT/scripts" "$PROFILE"

[ "$FAILED" -eq 0 ] || exit 1
