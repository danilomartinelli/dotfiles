#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Neovim configuration"

installer_link_tool_config nvim "Neovim init" init.vim

installer_success "Neovim configured"
