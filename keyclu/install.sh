#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring KeyClu"

installer_require_app KeyClu keyclu "/Applications/KeyClu.app"

# No `defaults write` here: launch-at-login is SMAppService territory on
# modern macOS and the app persists its own preferences on quit.
open -ga "$INSTALLER_APP" 2>/dev/null || true

installer_success "KeyClu ready — hold ⌘ to browse app shortcuts, or create custom ones in Settings"
installer_success "KeyClu configured"
