#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "configuring Aider"

# Aider reads this from $HOME rather than $HOME/.config, so it links through the
# linker directly instead of installer_link_tool_config.
#
# This topic used to render __DOTFILES_ROOT__ into the target and clear the old
# path with its own `rm` — a removal ADR 0001 reserves for the linker, chosen by
# a readlink comparison that re-derived the target classification the linker
# already owns. d215f545 took the last placeholder out of the source, so the
# rendering branch could no longer fire and the topic had been plain linking
# through dead code ever since.
installer_link_config --label "Aider config" \
  "$TOPIC_DIR/aider.conf.yml.symlink" "$HOME/.aider.conf.yml"

if command -v aider >/dev/null 2>&1; then
  installer_success "aider CLI available ($(aider --version 2>/dev/null))"
else
  installer_note "Install Aider with: mise install"
fi

installer_success "Aider configured"
