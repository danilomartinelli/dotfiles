#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Zed configuration"

installer_link_tool_config zed "Zed settings" settings.json
installer_link_tool_config zed "Zed keymap" keymap.json

ZED_BUNDLE="dev.zed.Zed"

installer_optional_app Zed zed /Applications/Zed.app

installer_claim_file_types Zed "$ZED_BUNDLE" \
  "Zed set as default app for tracked text/source extensions"
