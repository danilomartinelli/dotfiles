#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up atuin configuration"

# Atuin reads themes from ~/.atuin/themes, not from its configuration directory.
# atuin/env.zsh selects this one; config.toml stays machine-local.
installer_link_config --label "Atuin Catppuccin Macchiato theme" \
  "$TOPIC_DIR/catppuccin-macchiato-blue.toml" \
  "$HOME/.atuin/themes/catppuccin-macchiato-blue.toml"

installer_success "atuin configured"
