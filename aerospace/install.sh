#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up AeroSpace configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
DOTFILES_ROOT=$(CDPATH='' cd -P -- "$TOPIC_DIR/.." && pwd)
CONFIG_DIR="$HOME/.config/aerospace"
LINK_CONFIG="$DOTFILES_ROOT/_scripts/link-config"

mkdir -p "$CONFIG_DIR"

"$LINK_CONFIG" --label "AeroSpace config" \
  "$TOPIC_DIR/aerospace.toml" "$CONFIG_DIR/aerospace.toml"

# Also satisfy the ~/.aerospace.toml lookup path used by some docs/tools.
"$LINK_CONFIG" --label "~/.aerospace.toml" \
  "$TOPIC_DIR/aerospace.toml" "$HOME/.aerospace.toml"

if [ -d "/Applications/AeroSpace.app" ]; then
  echo "  → Start AeroSpace once from Spotlight/Raycast to grant Accessibility permission"
else
  echo "Warning: AeroSpace.app not found; install with brew bundle" >&2
fi

echo "✓ AeroSpace configured"
