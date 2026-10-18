#!/bin/sh
# Install the cluster addons for a profile.
#
# Safe to run repeatedly: every addon is installed with "helm upgrade --install",
# so an existing release is upgraded in place rather than duplicated.
#
# Every version is pinned here, together with the reason the addon exists, so
# that a run months from now produces the same cluster and a reader can see what
# each piece is standing in for.
#
# Usage: sh scripts/addons-up.sh [profile]        (default profile: local)
set -eu
. "$(dirname -- "$0")/lib.sh"

load_profile "${1:-local}"
require_docker
require_kind
command -v helm >/dev/null 2>&1 || die "helm is not on PATH"
command -v kubectl >/dev/null 2>&1 || die "kubectl is not on PATH"

cluster_present || die "cluster '$CLUSTER_NAME' does not exist; run 'sh scripts/up.sh $PROFILE' first"

# --- pinned versions ---------------------------------------------------------
# Kubernetes 1.36 needs the 0.9 line of the metrics server; 0.8 is for 1.33 and older.
METRICS_SERVER_CHART=3.14.0
# The gateway API custom resources are taken from the channel and revision that
# the gateway fabric release was built against, rather than from the newest
# upstream release, which is what the project documents and tests.
GATEWAY_API_REF=v2.7.2
GATEWAY_FABRIC_CHART=2.7.2
# The maintained classic controller. The one AKS still uses upstream is
# archived and gets no further fixes.
CLASSIC_INGRESS_CHART=2.7.3
CERT_MANAGER_CHART=1.21.2
# The only release certified against this Kubernetes minor, and the only minor
# the project supports at a time.
EXTERNAL_SECRETS_CHART=2.12.0

# --- helpers -----------------------------------------------------------------
helm_repo() {
	_name=$1
	_url=$2
	if ! helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "$_name"; then
		log "adding the $_name chart repository"
		helm repo add "$_name" "$_url" >/dev/null
	fi
	# A stale index can resolve a pinned version that no longer exists, so
	# refresh before any version is looked up.
	helm repo update "$_name" >/dev/null
}

# --- usage reporting ---------------------------------------------------------
# The managed cluster reports usage by default, so resource requests in a chart
# can be checked against real numbers rather than guesses.
install_metrics_server() {
	log "metrics-server chart $METRICS_SERVER_CHART"
	helm_repo metrics-server https://kubernetes-sigs.github.io/metrics-server/
	helm upgrade --install metrics-server metrics-server/metrics-server \
		--kube-context "$CONTEXT" \
		--namespace kube-system \
		--version "$METRICS_SERVER_CHART" \
		--values "$CLUSTER_ROOT/addons/metrics-server/values.yaml" \
		--wait --timeout 5m >/dev/null
}

# --- gateway API -------------------------------------------------------------
# Transport-layer routing, which the database needs, is only served from the
# experimental channel, and only with the feature flag switched on. Both are
# set here so that a later transport-layer route does not fail mysteriously.
install_gateway_api() {
	log "gateway API custom resources, experimental channel at $GATEWAY_API_REF"
	kubectl --context "$CONTEXT" kustomize \
		"https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=$GATEWAY_API_REF" \
		| kubectl --context "$CONTEXT" apply --server-side -f - >/dev/null
}

install_gateway_fabric() {
	log "gateway fabric chart $GATEWAY_FABRIC_CHART"
	helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
		--kube-context "$CONTEXT" \
		--namespace nginx-gateway --create-namespace \
		--version "$GATEWAY_FABRIC_CHART" \
		--set nginxGateway.gwAPIExperimentalFeatures.enable=true \
		--wait --timeout 5m >/dev/null
}

# --- classic ingress ---------------------------------------------------------
# Two installations, because a controller serves exactly one class. The first
# carries the class name the managed service uses and is the cluster default,
# so an Ingress that names no class is served as well. The second carries the
# familiar local name.
install_classic_ingress() {
	helm_repo nginx-stable https://helm.nginx.com/stable

	log "classic controller for the managed service's class name, chart $CLASSIC_INGRESS_CHART"
	helm upgrade --install ingress-aks-class nginx-stable/nginx-ingress \
		--kube-context "$CONTEXT" \
		--namespace ingress-aks-class --create-namespace \
		--version "$CLASSIC_INGRESS_CHART" \
		--values "$CLUSTER_ROOT/addons/nginx-ingress/aks-class.yaml" \
		--wait --timeout 5m >/dev/null

	log "classic controller for the local class name, chart $CLASSIC_INGRESS_CHART"
	helm upgrade --install ingress-nginx-class nginx-stable/nginx-ingress \
		--kube-context "$CONTEXT" \
		--namespace ingress-nginx-class --create-namespace \
		--version "$CLASSIC_INGRESS_CHART" \
		--values "$CLUSTER_ROOT/addons/nginx-ingress/nginx-class.yaml" \
		--wait --timeout 5m >/dev/null
}

# --- certificates ------------------------------------------------------------
install_cert_manager() {
	log "cert-manager chart $CERT_MANAGER_CHART"
	helm_repo jetstack https://charts.jetstack.io
	helm upgrade --install cert-manager jetstack/cert-manager \
		--kube-context "$CONTEXT" \
		--namespace cert-manager --create-namespace \
		--version "$CERT_MANAGER_CHART" \
		--set crds.enabled=true \
		--wait --timeout 5m >/dev/null

	log "local certificate authority"
	kubectl --context "$CONTEXT" apply -f "$CLUSTER_ROOT/addons/cert-manager/local-ca.yaml" >/dev/null
	kubectl --context "$CONTEXT" -n cert-manager wait \
		--for=condition=Ready certificate/local-ca --timeout=120s >/dev/null
}

install_metrics_server
install_gateway_api
install_gateway_fabric
install_classic_ingress
install_cert_manager

# --- secret delivery ---------------------------------------------------------
# Credentials live in the local secret store and are derived into the cluster,
# so that a chart consumes a Kubernetes secret and never a credential of its
# own. The same shape fronts a cloud secret manager in the production story.
install_external_secrets() {
	log "external-secrets chart $EXTERNAL_SECRETS_CHART"
	helm_repo external-secrets https://charts.external-secrets.io

	# The custom resources exceed the annotation size limit, so they are applied
	# server side rather than through the chart's own copy.
	kubectl --context "$CONTEXT" apply --server-side -f \
		"https://raw.githubusercontent.com/external-secrets/external-secrets/v$EXTERNAL_SECRETS_CHART/deploy/crds/bundle.yaml" >/dev/null

	helm upgrade --install external-secrets external-secrets/external-secrets \
		--kube-context "$CONTEXT" \
		--namespace external-secrets --create-namespace \
		--version "$EXTERNAL_SECRETS_CHART" \
		--set installCRDs=false \
		--wait --timeout 5m >/dev/null

	_token_file="$GENERATED_DIR/vault-$PROFILE-token"
	[ -f "$_token_file" ] || die "no scoped token at $_token_file; run 'sh scripts/vault-seed.sh $PROFILE' first"

	# A text file ends with a newline; a token must not. Handed over untrimmed,
	# the newline becomes part of the credential and the controller rejects the
	# store as containing non-printable characters, which reads like a bad
	# credential rather than a stray byte. Carriage returns are stripped too,
	# in case the file has ever been through a Windows editor.
	_token_trimmed="$GENERATED_DIR/.vault-$PROFILE-token.trimmed"
	tr -d '\r\n' < "$_token_file" > "$_token_trimmed"

	log "handing the scoped token to the cluster and wiring the store"
	kubectl --context "$CONTEXT" -n external-secrets create secret generic vault-token \
		--from-file=token="$(windows_path "$_token_trimmed")" \
		--dry-run=client -o yaml \
		| kubectl --context "$CONTEXT" apply -f - >/dev/null
	rm -f "$_token_trimmed"

	kubectl --context "$CONTEXT" apply \
		-f "$CLUSTER_ROOT/addons/external-secrets/cluster-secret-store.yaml" >/dev/null
	kubectl --context "$CONTEXT" apply \
		-f "$CLUSTER_ROOT/addons/external-secrets/database-credentials.yaml" >/dev/null

	log "waiting for the secret to be derived from the store"
	# Generous, because the controller revalidates the store on a backoff: after
	# a store has been invalid once, the next attempt can be minutes away even
	# though the fix was already applied.
	kubectl --context "$CONTEXT" -n database wait \
		--for=condition=Ready externalsecret/agents-db-credentials --timeout=300s >/dev/null
}

install_external_secrets

# The gateway and its listener certificate can only be created once the
# certificate authority exists, so this runs last: applying a certificate before
# cert-manager is installed would leave it waiting rather than failing.
install_gateway_resources() {
	log "gateway, its proxy configuration and its listener certificate"
	kubectl --context "$CONTEXT" apply -f "$CLUSTER_ROOT/addons/nginx-gateway-fabric/gateway.yaml" >/dev/null
	kubectl --context "$CONTEXT" -n default wait \
		--for=condition=Ready certificate/gateway-tls --timeout=120s >/dev/null
	kubectl --context "$CONTEXT" -n default wait \
		--for=condition=Programmed gateway/local --timeout=120s >/dev/null
}

install_gateway_resources

printf '\n'
log "addons installed on cluster '$CLUSTER_NAME'"
log "usage:      kubectl --context $CONTEXT top nodes"
log "classes:    kubectl --context $CONTEXT get ingressclass"
log "gateway:    kubectl --context $CONTEXT get gatewayclass"
