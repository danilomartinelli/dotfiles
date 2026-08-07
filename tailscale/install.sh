#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Tailscale"

installer_require_app Tailscale tailscale-app "/Applications/Tailscale.app"

# Only open on first install; subsequent runs skip to avoid interrupting work.
first_run_marker="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/tailscale-opened"
if [ ! -f "$first_run_marker" ]; then
  open -ga "$INSTALLER_APP" 2>/dev/null || true
  mkdir -p "$(dirname "$first_run_marker")"
  touch "$first_run_marker"
fi

if command -v tailscale >/dev/null 2>&1; then
  installer_success "tailscale CLI available"
else
  installer_note "Open Tailscale once and enable the CLI from the menu bar app if needed"
fi

installer_success "Tailscale configured"
