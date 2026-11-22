#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Neovim configuration"

installer_link_tool_config nvim "Neovim init" init.lua
# Neovim writes this file when a plugin is added or updated, so such a change
# lands here as a diff to keep or discard.
installer_link_tool_config nvim "Neovim plugin lock" nvim-pack-lock.json

installer_success "Neovim configured"
