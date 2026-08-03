#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring Tailscale"

if [ -d "/Applications/Tailscale.app" ]; then
  open -ga "/Applications/Tailscale.app" 2>/dev/null || true
else
  echo "Warning: Tailscale.app not installed yet" >&2
  echo "  Install with: brew install --cask tailscale-app" >&2
  exit 0
fi

if command -v tailscale >/dev/null 2>&1; then
  echo "  ✓ tailscale CLI available"
else
  echo "  → Open Tailscale once and enable the CLI from the menu bar app if needed"
fi

echo "✓ Tailscale configured"
