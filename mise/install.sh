#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_command mise

mise_policy=$DOTFILES_ROOT/_scripts/mise-policy

installer_link_tool_config mise "Mise config" config.toml
installer_link_tool_config mise "Mise lock" mise.lock
sh "$TOPIC_DIR/_configure-trust.sh"

installer_link_config --remove-owned --label "legacy Mise link $HOME/.mise.toml" \
  "$TOPIC_DIR/mise.toml.symlink" "$HOME/.mise.toml"
installer_link_config --remove-owned --label "legacy Mise link $HOME/.mise.lock" \
  "$TOPIC_DIR/mise.lock.symlink" "$HOME/.mise.lock"

# Install exactly what the lock records and never write it. A plain install
# rewrites the lock into a shape `mise lock` does not produce, so every run
# dirtied the tree.
installer_banner "Installing Mise runtimes"
if "$mise_policy" "$DOTFILES_ROOT" run install; then
  installer_success "Mise runtimes installed successfully"
else
  installer_error "Failed to install Mise runtimes"
  installer_hint "If a declaration changed, run _scripts/mise-policy <checkout> lock <tool>... for the selected tools and review mise/mise.lock."
  exit 1
fi

sh "$TOPIC_DIR/_post-install.sh"
