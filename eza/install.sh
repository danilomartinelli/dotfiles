#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up eza configuration"

# eza/env.zsh points EZA_CONFIG_DIR here; without it eza reads
# ~/Library/Application Support/eza on macOS.
installer_link_tool_config eza "eza theme" theme.yml

installer_success "eza configured"
