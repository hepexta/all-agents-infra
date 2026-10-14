#!/bin/sh
# Shared helpers for the local cluster scripts.
#
# Sourced by up.sh, down.sh and status.sh; not meant to be run on its own.
# See ../README.md for usage.

set -eu

CLUSTER_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILES_DIR="$CLUSTER_ROOT/profiles"
GENERATED_DIR="$CLUSTER_ROOT/.generated"

# The kind release that added the kubeadm API version required by node images
# for Kubernetes 1.36 and newer. Older kind releases do not fail loudly here:
# they produce a cluster that never becomes Ready, which is far harder to
# diagnose than a version check.
REQUIRED_KIND_VERSION=0.33.0

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# load_profile <name> - read profiles/<name>.env and derive the context name.
load_profile() {
	_profile=$1
	_profile_file="$PROFILES_DIR/$_profile.env"
	[ -f "$_profile_file" ] || die "no such profile '$_profile' (looked for $_profile_file)"
	# shellcheck source=/dev/null
	. "$_profile_file"

	PROFILE=$_profile
	: "${CLUSTER_NAME:?CLUSTER_NAME must be set in $PROFILE}"
	: "${KUBERNETES_VERSION:?KUBERNETES_VERSION must be set in $PROFILE}"
	: "${NODE_IMAGE:?NODE_IMAGE must be set in $PROFILE}"
	: "${CONTROL_PLANE_NODES:=1}"
	: "${WORKER_NODES:=2}"
	: "${HOST_PORTS:=}"
	: "${LISTEN_ADDRESS:=127.0.0.1}"

	[ "$CONTROL_PLANE_NODES" = "1" ] || die "kind supports exactly one control plane node in this setup; CONTROL_PLANE_NODES is $CONTROL_PLANE_NODES"
	case "$WORKER_NODES" in
		''|*[!0-9]*) die "WORKER_NODES must be a number, got '$WORKER_NODES'" ;;
	esac

	CONTEXT="kind-$CLUSTER_NAME"
	CONFIG_FILE="$GENERATED_DIR/$PROFILE-kind.yaml"
	PREVIOUS_CONTEXT_FILE="$GENERATED_DIR/$PROFILE.previous-context"
}

require_docker() {
	docker info >/dev/null 2>&1 || die "the container runtime is not answering; start Docker Desktop and try again"
}

# Fail before touching anything when kind is too old to run the pinned image.
require_kind() {
	command -v kind >/dev/null 2>&1 || die "kind is not on PATH"
	_installed=$(kind version 2>/dev/null | sed -n 's/^kind v\([0-9][0-9.]*\).*/\1/p')
	[ -n "$_installed" ] || die "could not read a version out of 'kind version'"
	if [ "$(printf '%s\n%s\n' "$REQUIRED_KIND_VERSION" "$_installed" | sort -V | head -n1)" != "$REQUIRED_KIND_VERSION" ]; then
		die "kind $_installed cannot run $NODE_IMAGE. kind $REQUIRED_KIND_VERSION or newer is required, because the node images for Kubernetes 1.36 and later need a kubeadm API version that older kind releases do not send. On Windows, from an elevated shell: choco upgrade kind -y"
	fi
}

cluster_present() {
	kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"
}

# kind is a native Windows binary and cannot read a Git Bash path such as
# /c/Work/..., so hand it a Windows path with forward slashes instead.
windows_path() {
	_dir=$(dirname -- "$1")
	_base=$(basename -- "$1")
	if _win=$(CDPATH= cd -- "$_dir" && pwd -W 2>/dev/null); then
		printf '%s/%s\n' "$_win" "$_base"
	elif command -v cygpath >/dev/null 2>&1; then
		printf '%s/%s\n' "$(cygpath -m "$_dir")" "$_base"
	else
		die "cannot convert '$_dir' to a Windows path; run these scripts from Git Bash"
	fi
}
