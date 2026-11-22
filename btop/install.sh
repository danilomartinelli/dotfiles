#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up btop configuration"

# btop writes its settings back to btop.conf, so a change made in its menu lands
# here as a diff to keep or discard.
installer_link_tool_config btop "btop settings" btop.conf
installer_link_config --label "btop Catppuccin Macchiato theme" \
  "$TOPIC_DIR/catppuccin_macchiato.theme" \
  "$(installer_config_dir btop)/themes/catppuccin_macchiato.theme"

installer_success "btop configured"
