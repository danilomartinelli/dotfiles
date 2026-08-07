#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "configuring Aider"

CONFIG_SOURCE="$TOPIC_DIR/aider.conf.yml.symlink"
CONFIG_TARGET="$HOME/.aider.conf.yml"

mkdir -p "$(dirname "$CONFIG_TARGET")"

# Render the __DOTFILES_ROOT__ placeholder before linking. Aider is the only
# tool that needs a real file (not a symlink) here because the symlink target
# is also a `.symlink` file in the repo, so we must follow the chain and write
# the resolved content once.
if [ -L "$CONFIG_TARGET" ] && [ "$(readlink "$CONFIG_TARGET")" = "$CONFIG_SOURCE" ] && grep -q '__DOTFILES_ROOT__' "$CONFIG_SOURCE"; then
  rendered=$(mktemp)
  sed "s|__DOTFILES_ROOT__|$DOTFILES_ROOT|g" "$CONFIG_SOURCE" >"$rendered"
  rm "$CONFIG_TARGET"
  mv "$rendered" "$CONFIG_TARGET"
  installer_success "Rendered __DOTFILES_ROOT__ in $CONFIG_TARGET"
elif [ ! -e "$CONFIG_TARGET" ]; then
  if grep -q '__DOTFILES_ROOT__' "$CONFIG_SOURCE"; then
    rendered=$(mktemp)
    sed "s|__DOTFILES_ROOT__|$DOTFILES_ROOT|g" "$CONFIG_SOURCE" >"$rendered"
    mv "$rendered" "$CONFIG_TARGET"
  else
    ln -s "$CONFIG_SOURCE" "$CONFIG_TARGET"
  fi
  installer_success "Linked $CONFIG_TARGET -> $CONFIG_SOURCE"
fi

if command -v aider >/dev/null 2>&1; then
  installer_success "aider CLI available ($(aider --version 2>/dev/null))"
else
  installer_note "Install Aider with: mise install"
fi

installer_note "AGENTS.md auto-loads from $DOTFILES_ROOT/_shared/agents/AGENTS.md"
installer_success "Aider configured"
