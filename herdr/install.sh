#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Herdr configuration"

# Herdr rewrites most of ~/.config/herdr-app on every start, so the files are
# linked one by one and the directory stays its own. The Settings window writes
# settings.json, so a change made there lands here as a diff to keep or
# discard. keys.json is left to the app: an untouched one receives the
# shortcuts each release adds, and an edited one never does.
installer_link_tool_config herdr-app "Herdr settings" settings.json
installer_link_tool_config herdr-app "Herdr programs" programs.json

# The palettes Ghostty and OpenCode use, which Herdr does not ship.
installer_link_tool_config herdr-app "Herdr dark theme" themes/catppuccin-macchiato.json
installer_link_tool_config herdr-app "Herdr light theme" themes/catppuccin-latte.json

installer_success "Herdr configured"
