#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Zed configuration"

CONFIG_DIR=$(installer_config_dir zed)

mkdir -p "$CONFIG_DIR"

installer_link_config --label "Zed settings" \
  "$TOPIC_DIR/settings.json" "$CONFIG_DIR/settings.json"

installer_link_config --label "Zed keymap" \
  "$TOPIC_DIR/keymap.json" "$CONFIG_DIR/keymap.json"

ZED_BUNDLE="dev.zed.Zed"

installer_optional_app Zed zed /Applications/Zed.app

installer_skip_if_applied zed-associations "file associations" "Zed configured"

installer_optional_command duti "duti is required to set Zed as the default text editor"

installer_apply_associations Zed "$ZED_BUNDLE" \
  "Zed set as default app for tracked text/source extensions"

installer_mark_applied zed-associations

installer_success "Zed configured"
