#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up OrbStack Docker engine defaults"

CONFIG_DIR="$HOME/.orbstack/config"
SOURCE="$TOPIC_DIR/docker.json"
TARGET="$CONFIG_DIR/docker.json"

mkdir -p "$CONFIG_DIR"

installer_link_config --policy preserve-existing --label "OrbStack docker.json" \
  "$SOURCE" "$TARGET"

# Prefer OrbStack as the active Docker context when available.
if command -v docker >/dev/null 2>&1 && docker context ls >/dev/null 2>&1; then
  if docker context ls --format '{{.Name}}' 2>/dev/null | grep -qx 'orbstack'; then
    if docker context use orbstack >/dev/null 2>&1; then
      installer_success "Docker context set to orbstack"
    fi
  fi
fi

# Ensure Docker CLI uses the macOS keychain credential helper after Desktop migrations.
DOCKER_CLI_CONFIG="$HOME/.docker/config.json"
if [ ! -f "$DOCKER_CLI_CONFIG" ]; then
  mkdir -p "$HOME/.docker"
  printf '%s\n' '{' '  "credsStore": "osxkeychain"' '}' >"$DOCKER_CLI_CONFIG"
  installer_success "Created ~/.docker/config.json with osxkeychain"
fi

installer_success "OrbStack configured"
