#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Bartender"

APP=""
for candidate in "/Applications/Bartender 6.app" "/Applications/Bartender.app"; do
  if [ -d "$candidate" ]; then
    APP=$candidate
    break
  fi
done

if [ -z "$APP" ]; then
  installer_warn "Bartender not installed yet; skipping preferences"
  installer_hint "Install with: brew install --cask bartender"
  exit 0
fi

# Bartender 5/6 share the Surtees Studios preference domain.
defaults write com.surteesstudios.Bartender SUEnableAutomaticChecks -bool true 2>/dev/null || true
defaults write com.surteesstudios.Bartender showOnStartup -bool true 2>/dev/null || true
defaults write com.surteesstudios.Bartender updateAutoUpdate -bool true 2>/dev/null || true

# Open once so macOS can prompt for Accessibility / Screen Recording if needed.
open -ga "$APP" 2>/dev/null || true

installer_success "Bartender preferences applied (hide/show items are configured in the app UI)"
installer_success "Bartender configured"
