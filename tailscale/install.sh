#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Tailscale"

installer_optional_app Tailscale tailscale-app "/Applications/Tailscale.app"

if command -v tailscale >/dev/null 2>&1; then
  installer_success "tailscale CLI available"
else
  installer_note "Open Tailscale manually and enable the CLI from the menu bar app if needed"
fi

installer_success "Tailscale configured"
