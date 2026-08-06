#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up AeroSpace configuration"

CONFIG_DIR="$HOME/.config/aerospace"

mkdir -p "$CONFIG_DIR"

# Single destination on purpose: AeroSpace uses the first config it finds,
# and a second link (~/.aerospace.toml) invites silent divergence.
installer_link_config --label "AeroSpace config" \
  "$TOPIC_DIR/aerospace.toml" "$CONFIG_DIR/aerospace.toml"

if [ -d "/Applications/AeroSpace.app" ]; then
  installer_note "Start AeroSpace once from Spotlight/Raycast to grant Accessibility permission"
else
  installer_warn "AeroSpace.app not found; install with brew bundle"
fi

installer_success "AeroSpace configured"
