#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up AeroSpace configuration"

CONFIG_DIR="$HOME/.config/aerospace"

mkdir -p "$CONFIG_DIR"

installer_link_config --label "AeroSpace config" \
  "$TOPIC_DIR/aerospace.toml" "$CONFIG_DIR/aerospace.toml"

# Also satisfy the ~/.aerospace.toml lookup path used by some docs/tools.
installer_link_config --label "~/.aerospace.toml" \
  "$TOPIC_DIR/aerospace.toml" "$HOME/.aerospace.toml"

if [ -d "/Applications/AeroSpace.app" ]; then
  installer_note "Start AeroSpace once from Spotlight/Raycast to grant Accessibility permission"
else
  installer_warn "AeroSpace.app not found; install with brew bundle"
fi

installer_success "AeroSpace configured"
