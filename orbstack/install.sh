#!/bin/sh

set -e

if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up OrbStack Docker engine defaults"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
DOTFILES_ROOT=$(CDPATH='' cd -P -- "$TOPIC_DIR/.." && pwd)
CONFIG_DIR="$HOME/.orbstack/config"
SOURCE="$TOPIC_DIR/docker.json"
TARGET="$CONFIG_DIR/docker.json"
LINK_CONFIG="$DOTFILES_ROOT/_scripts/link-config"

mkdir -p "$CONFIG_DIR"

"$LINK_CONFIG" --policy preserve-existing --label "OrbStack docker.json" \
  "$SOURCE" "$TARGET"

# Prefer OrbStack as the active Docker context when available.
if command -v docker >/dev/null 2>&1 && docker context ls >/dev/null 2>&1; then
  if docker context ls --format '{{.Name}}' 2>/dev/null | grep -qx 'orbstack'; then
    if docker context use orbstack >/dev/null 2>&1; then
      echo "  ✓ Docker context set to orbstack"
    fi
  fi
fi

# Ensure Docker CLI uses the macOS keychain credential helper after Desktop migrations.
DOCKER_CLI_CONFIG="$HOME/.docker/config.json"
if [ ! -f "$DOCKER_CLI_CONFIG" ]; then
  mkdir -p "$HOME/.docker"
  printf '%s\n' '{' '  "credsStore": "osxkeychain"' '}' >"$DOCKER_CLI_CONFIG"
  echo "  ✓ Created ~/.docker/config.json with osxkeychain"
fi

echo "✓ OrbStack configured"
