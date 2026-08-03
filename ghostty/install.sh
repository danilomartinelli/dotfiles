#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up Ghostty configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
CONFIG_DIR="$HOME/.config/ghostty"

mkdir -p "$CONFIG_DIR"

target="$CONFIG_DIR/config"
if [ -L "$target" ] && [ "$(readlink "$target")" = "$TOPIC_DIR/config" ]; then
  echo "  ✓ Ghostty config already linked"
elif [ -e "$target" ] && [ ! -L "$target" ]; then
  backup="$CONFIG_DIR/config.backup"
  if [ -e "$backup" ]; then
    echo "Warning: $target and $backup exist; leaving config untouched" >&2
  else
    mv "$target" "$backup"
    ln -s "$TOPIC_DIR/config" "$target"
    echo "  → Existing config moved to $backup"
    echo "  ✓ Ghostty config linked"
  fi
else
  ln -sfn "$TOPIC_DIR/config" "$target"
  echo "  ✓ Ghostty config linked"
fi

# Register Ghostty as the default handler for Unix executables (idempotent).
if defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers 2>/dev/null | grep -q "com.mitchellh.ghostty"; then
  echo "  ✓ Ghostty already the default terminal handler"
elif defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{LSHandlerContentType=public.unix-executable;LSHandlerRoleAll=com.mitchellh.ghostty;}' 2>/dev/null; then
  echo "  ✓ Ghostty set as default terminal handler"
else
  echo "Warning: Failed to set Ghostty as default terminal handler" >&2
  echo "  You may need to set it manually in System Settings" >&2
fi

echo "✓ Ghostty configured"
