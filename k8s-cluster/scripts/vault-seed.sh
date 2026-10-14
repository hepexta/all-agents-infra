#!/bin/sh
# Seed this project's database credentials into the local secret store and mint
# a token scoped to reading them, for the cluster to use.
#
# Idempotent: an existing password is left alone, so re-running after the store
# has been restarted restores the same credentials rather than silently
# changing them under a running database. Pass --rotate to replace them.
#
# The profile name doubles as the environment name, so the local profile writes
# to secret/agents-infra/local/... and a later profile writes its own prefix.
#
# Usage: sh scripts/vault-seed.sh [profile] [--rotate]
set -eu
. "$(dirname -- "$0")/lib.sh"

ROTATE=0
PROFILE_ARG=local
for _arg in "$@"; do
	case "$_arg" in
		--rotate) ROTATE=1 ;;
		-*) die "unknown option '$_arg'" ;;
		*) PROFILE_ARG=$_arg ;;
	esac
done

load_profile "$PROFILE_ARG"

VAULT_CONTAINER=${VAULT_CONTAINER:-vault-service}
VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}
# Public development placeholder baked into the image this container runs. It is
# used here only to seed and to mint the scoped token; the cluster never sees it.
VAULT_ROOT_TOKEN=${VAULT_ROOT_TOKEN:-dev-token}
export VAULT_ADDR

VAULT_MOUNT=${VAULT_MOUNT:-secret}
VAULT_PREFIX="agents-infra/$PROFILE"
VAULT_PATH="$VAULT_MOUNT/$VAULT_PREFIX/database"
VAULT_POLICY="agents-infra-$PROFILE-read"
TOKEN_FILE="$GENERATED_DIR/vault-$PROFILE-token"

DB_USER=${DB_USER:-agents}
DB_NAME=${DB_NAME:-allagents}

command -v vault >/dev/null 2>&1 || die "the vault CLI is not on PATH; install it (on Windows: 'choco install vault -y' from an elevated shell)"

# Bring the store up first, so the rest of this script can assume it answers.
sh "$CLUSTER_ROOT/scripts/vault-up.sh"

VAULT_TOKEN=$VAULT_ROOT_TOKEN
export VAULT_TOKEN

if [ "$ROTATE" = "1" ]; then
	log "rotating credentials at $VAULT_PATH"
	_password=
else
	_password=$(vault kv get -field=password "$VAULT_PATH" 2>/dev/null || true)
	[ -n "$_password" ] && log "keeping the existing credential at $VAULT_PATH"
fi

if [ -z "$_password" ]; then
	# Alphanumeric only, so the value survives every quoting path between here,
	# a Kubernetes secret and a JDBC URL without escaping.
	_password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
	log "generated a new credential for $VAULT_PATH"
fi

vault kv put "$VAULT_PATH" \
	username="$DB_USER" \
	password="$_password" \
	database="$DB_NAME" >/dev/null
log "wrote username, password and database to $VAULT_PATH"

# Read-only policy, scoped to this environment's prefix. Written from standard
# input so the policy lives with the script that needs it.
vault policy write "$VAULT_POLICY" - >/dev/null <<EOF
# Read this project's database credentials for one environment and nothing else.
path "$VAULT_MOUNT/data/$VAULT_PREFIX/*" {
  capabilities = ["read"]
}
path "$VAULT_MOUNT/metadata/$VAULT_PREFIX/*" {
  capabilities = ["read", "list"]
}
EOF
log "wrote policy $VAULT_POLICY scoped to $VAULT_MOUNT/data/$VAULT_PREFIX/*"

# A periodic token, so the controller can renew it indefinitely instead of it
# expiring out from under a running cluster.
_token=$(vault token create \
	-policy="$VAULT_POLICY" \
	-period=720h \
	-display-name="eso-agents-infra-$PROFILE" \
	-field=token)

mkdir -p "$GENERATED_DIR"
# Correct on a POSIX filesystem. On Windows the mode is not enforced by the
# filesystem, so the token's protection there is that it lives in a directory
# ignored by version control inside the user's own profile.
umask 077
printf '%s\n' "$_token" > "$TOKEN_FILE"
log "wrote the scoped cluster token to $TOKEN_FILE (ignored by version control)"

printf '\n'
log "seeded:  $VAULT_PATH (keys: username, password, database)"
log "policy:  $VAULT_POLICY"
log "token:   $TOKEN_FILE"
log "inspect with: VAULT_ADDR=$VAULT_ADDR VAULT_TOKEN=$VAULT_ROOT_TOKEN vault kv get $VAULT_PATH"
