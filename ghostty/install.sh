#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up Ghostty configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
DOTFILES_ROOT=$(CDPATH='' cd -P -- "$TOPIC_DIR/.." && pwd)
CONFIG_DIR="$HOME/.config/ghostty"
LINK_CONFIG="$DOTFILES_ROOT/_scripts/link-config"

mkdir -p "$CONFIG_DIR"

"$LINK_CONFIG" --label "Ghostty config" "$TOPIC_DIR/config" "$CONFIG_DIR/config"

# Register Ghostty as the default handler for Unix executables (idempotent).
if [ ! -d "/Applications/Ghostty.app" ]; then
  echo "Warning: Ghostty not found at /Applications/Ghostty.app; skipping default terminal handler" >&2
elif defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers 2>/dev/null | grep -q "com.mitchellh.ghostty"; then
  echo "  ✓ Ghostty already the default terminal handler"
elif defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{LSHandlerContentType=public.unix-executable;LSHandlerRoleAll=com.mitchellh.ghostty;}' 2>/dev/null; then
  echo "  ✓ Ghostty set as default terminal handler"
else
  echo "Warning: Failed to set Ghostty as default terminal handler" >&2
  echo "  You may need to set it manually in System Settings" >&2
fi

echo "✓ Ghostty configured"
