#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Bartender"

installer_require_app Bartender bartender \
  "/Applications/Bartender 6.app" "/Applications/Bartender.app"

# No `defaults write` here: modern Bartender manages launch-at-login via
# SMAppService and persists its own preferences on quit, so scripted writes
# are silently overwritten. Everything is configured in the app UI.

# Open once so macOS can prompt for Accessibility / Screen Recording if needed.
# Only open on first install; subsequent runs skip to avoid interrupting work.
first_run_marker="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/bartender-opened"
if [ ! -f "$first_run_marker" ]; then
  open -ga "$INSTALLER_APP" 2>/dev/null || true
  mkdir -p "$(dirname "$first_run_marker")"
  touch "$first_run_marker"
fi

installer_success "Bartender configured (hide/show items are configured in the app UI)"
