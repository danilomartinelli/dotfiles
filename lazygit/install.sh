#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up lazygit configuration"

# lazygit looks in ~/Library/Application Support unless XDG_CONFIG_HOME is set,
# and .commonrc pins that to ~/.config for every shell lazygit starts from.
installer_link_tool_config lazygit "lazygit settings" config.yml

installer_success "lazygit configured"
