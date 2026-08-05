#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring KeyClu"

if [ ! -d "/Applications/KeyClu.app" ]; then
  installer_warn "KeyClu not installed yet; skipping preferences"
  echo "  Install with: brew install --cask keyclu" >&2
  exit 0
fi

# Show shortcut overlay when holding Command (KeyClu's primary UX).
defaults write com.0804Team.KeyClu SUEnableAutomaticChecks -bool true 2>/dev/null || true
defaults write com.0804Team.KeyClu launchAtLogin -bool true 2>/dev/null || true

open -ga "/Applications/KeyClu.app" 2>/dev/null || true

installer_success "KeyClu ready — hold ⌘ to browse app shortcuts, or create custom ones in Settings"
installer_success "KeyClu configured"
