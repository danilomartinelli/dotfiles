#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

# Validate mise is installed
if ! command -v mise >/dev/null 2>&1; then
  installer_error "mise is not installed"
  installer_hint "Install with: brew install mise"
  exit 1
fi

# Trust the linked global config so installs never prompt interactively.
MISE_CONFIG="${MISE_GLOBAL_CONFIG_FILE:-$HOME/.mise.toml}"
if [ -e "$MISE_CONFIG" ]; then
  mise trust "$MISE_CONFIG" >/dev/null 2>&1 || true
fi

installer_banner "Installing Mise runtimes"
if mise install; then
  installer_success "Mise runtimes installed successfully"
else
  installer_error "Failed to install Mise runtimes"
  exit 1
fi

# Remove runtimes no longer declared and stale patch versions.
mise prune --yes >/dev/null 2>&1 || true
