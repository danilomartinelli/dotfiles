#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "configuring Aider"

# This topic links nothing. aider.conf.yml.symlink is a *.symlink file, so
# _scripts/link-dotfiles already links it to $HOME/.aider.conf.yml, and setup
# runs that before any topic installer in both bootstrap and update.
#
# The installer used to render __DOTFILES_ROOT__ into that same target and clear
# the old path with its own `rm`. d215f545 removed the last placeholder from the
# source, so the rendering branch could not fire and what remained only ever ran
# when the target was absent — which, after link-dotfiles, it never is. Replacing
# that with a plain installer_link_config looked like the tidy fix and was worse:
# `dot` passes --batch skip, link-dotfiles honours it as preserve-existing, and a
# second link call here would then re-decide the same target under the default
# replace-with-backup and move a file the run had just promised to keep.

if command -v aider >/dev/null 2>&1; then
  installer_success "aider CLI available ($(aider --version 2>/dev/null))"
else
  installer_note "Install Aider with: mise install"
fi

installer_success "Aider configured"
