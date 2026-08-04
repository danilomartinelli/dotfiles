#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring Raycast script commands"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
SCRIPTS_DIR="$TOPIC_DIR/scripts"

if [ ! -d "/Applications/Raycast.app" ]; then
  echo "Warning: Raycast not installed yet" >&2
  echo "  Install with: brew install --cask raycast" >&2
  exit 0
fi

# Raycast stores most settings in its own sync store; script commands are the
# durable, repo-friendly surface. Point Raycast at this directory once:
#   Raycast → Settings → Extensions → Script Commands → Add Directories
echo "  ✓ Script commands live in $SCRIPTS_DIR"
echo "  → Add that folder in Raycast → Settings → Extensions → Script Commands"

# Sensible first-run defaults when the preference domain exists.
defaults write com.raycast.macos SUEnableAutomaticChecks -bool true 2>/dev/null || true

echo "✓ Raycast configured"
