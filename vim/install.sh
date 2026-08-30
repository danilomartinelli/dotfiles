#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Neovim configuration"

CONFIG_DIR=$(installer_config_dir nvim)

mkdir -p "$CONFIG_DIR"

installer_link_config --label "Neovim init" "$TOPIC_DIR/init.vim" "$CONFIG_DIR/init.vim"

installer_success "Neovim configured"
