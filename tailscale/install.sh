#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Tailscale"

if [ -d "/Applications/Tailscale.app" ]; then
  open -ga "/Applications/Tailscale.app" 2>/dev/null || true
else
  installer_warn "Tailscale.app not installed yet"
  echo "  Install with: brew install --cask tailscale-app" >&2
  exit 0
fi

if command -v tailscale >/dev/null 2>&1; then
  installer_success "tailscale CLI available"
else
  installer_note "Open Tailscale once and enable the CLI from the menu bar app if needed"
fi

installer_success "Tailscale configured"
