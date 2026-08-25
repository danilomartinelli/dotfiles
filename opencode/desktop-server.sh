#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)

# The Desktop embedded sidecar currently does not dispatch local plugin hooks.
# Run the same pinned CLI runtime as a loopback-only backend so permissions,
# leases, worktrees, plans, and delegations retain their managed semantics.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/env.zsh"

export OPENCODE_CLIENT=desktop-external
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if ! command -v mise >/dev/null 2>&1; then
	printf '%s\n' "opencode desktop server: mise is not available" >&2
	exit 127
fi

exec mise exec -- opencode serve \
	--hostname 127.0.0.1 \
	--port "${OPENCODE_DESKTOP_SERVER_PORT:-4097}"
