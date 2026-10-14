#!/bin/sh
# Make sure the local secret store is running and answering.
#
# Safe to run repeatedly. This repository does not create or configure the
# store: it belongs to another project and is reused here, so the most this
# does is start the existing container and wait for it to answer.
#
# Usage: sh scripts/vault-up.sh
set -eu
. "$(dirname -- "$0")/lib.sh"

VAULT_CONTAINER=${VAULT_CONTAINER:-vault-service}
VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}
export VAULT_ADDR
export VAULT_CONTAINER

require_docker

_state=$(docker inspect --format '{{.State.Status}}' "$VAULT_CONTAINER" 2>/dev/null || true)
[ -n "$_state" ] || die "container '$VAULT_CONTAINER' does not exist; this repository reuses an existing secret store rather than creating one"

if [ "$_state" = "running" ]; then
	log "secret store container '$VAULT_CONTAINER' is already running"
else
	log "secret store container '$VAULT_CONTAINER' is $_state, starting it"
	docker start "$VAULT_CONTAINER" >/dev/null
fi

# The health endpoint answers 200 only when the store is unsealed and active,
# so a successful response here means it is genuinely usable.
log "waiting for $VAULT_ADDR to report healthy"
_i=0
while [ "$_i" -lt 30 ]; do
	if curl -fsS "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
		log "secret store is up and unsealed at $VAULT_ADDR"
		exit 0
	fi
	_i=$((_i + 1))
	sleep 1
done

die "the secret store did not become healthy within 30 seconds; check 'docker logs $VAULT_CONTAINER'"
