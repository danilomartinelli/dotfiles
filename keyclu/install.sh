#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring KeyClu"

if [ ! -d "/Applications/KeyClu.app" ]; then
  echo "Warning: KeyClu not installed yet; skipping preferences" >&2
  echo "  Install with: brew install --cask keyclu" >&2
  exit 0
fi

# Show shortcut overlay when holding Command (KeyClu's primary UX).
defaults write com.0804Team.KeyClu SUEnableAutomaticChecks -bool true 2>/dev/null || true
defaults write com.0804Team.KeyClu launchAtLogin -bool true 2>/dev/null || true

open -ga "/Applications/KeyClu.app" 2>/dev/null || true

echo "  ✓ KeyClu ready — hold ⌘ to browse app shortcuts, or create custom ones in Settings"
echo "✓ KeyClu configured"
