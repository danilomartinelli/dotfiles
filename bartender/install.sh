#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring Bartender"

APP=""
for candidate in "/Applications/Bartender 6.app" "/Applications/Bartender.app"; do
  if [ -d "$candidate" ]; then
    APP=$candidate
    break
  fi
done

if [ -z "$APP" ]; then
  echo "Warning: Bartender not installed yet; skipping preferences" >&2
  echo "  Install with: brew install --cask bartender" >&2
  exit 0
fi

# Bartender 5/6 share the Surtees Studios preference domain.
defaults write com.surteesstudios.Bartender SUEnableAutomaticChecks -bool true 2>/dev/null || true
defaults write com.surteesstudios.Bartender showOnStartup -bool true 2>/dev/null || true
defaults write com.surteesstudios.Bartender updateAutoUpdate -bool true 2>/dev/null || true

# Open once so macOS can prompt for Accessibility / Screen Recording if needed.
open -ga "$APP" 2>/dev/null || true

echo "  ✓ Bartender preferences applied (hide/show items are configured in the app UI)"
echo "✓ Bartender configured"
