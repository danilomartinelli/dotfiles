#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up AeroSpace configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
CONFIG_DIR="$HOME/.config/aerospace"

mkdir -p "$CONFIG_DIR"

target="$CONFIG_DIR/aerospace.toml"
if [ -L "$target" ] && [ "$(readlink "$target")" = "$TOPIC_DIR/aerospace.toml" ]; then
  echo "  ✓ AeroSpace config already linked"
elif [ -e "$target" ] && [ ! -L "$target" ]; then
  backup="$CONFIG_DIR/aerospace.toml.backup"
  if [ -e "$backup" ]; then
    echo "Warning: $target and $backup exist; leaving config untouched" >&2
  else
    mv "$target" "$backup"
    ln -s "$TOPIC_DIR/aerospace.toml" "$target"
    echo "  → Existing config moved to $backup"
    echo "  ✓ AeroSpace config linked"
  fi
else
  ln -sfn "$TOPIC_DIR/aerospace.toml" "$target"
  echo "  ✓ AeroSpace config linked"
fi

# Also satisfy the ~/.aerospace.toml lookup path used by some docs/tools.
home_target="$HOME/.aerospace.toml"
if [ -L "$home_target" ] || [ ! -e "$home_target" ]; then
  ln -sfn "$TOPIC_DIR/aerospace.toml" "$home_target"
  echo "  ✓ ~/.aerospace.toml linked"
fi

if [ -d "/Applications/AeroSpace.app" ]; then
  echo "  → Start AeroSpace once from Spotlight/Raycast to grant Accessibility permission"
else
  echo "Warning: AeroSpace.app not found; install with brew bundle" >&2
fi

echo "✓ AeroSpace configured"
