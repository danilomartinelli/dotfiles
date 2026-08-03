#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Dotfiles
# @raycast.mode silent
# @raycast.packageName Dotfiles
# @raycast.icon 📂
# @raycast.description Open the active dotfiles checkout in $EDITOR

set -euo pipefail

ROOT="${DOTFILES_ROOT:-}"
if [ -z "$ROOT" ] && [ -L "$HOME/.dotfiles-root" ]; then
  ROOT=$(readlink "$HOME/.dotfiles-root")
fi
if [ -z "$ROOT" ]; then
  ROOT="$HOME/.dotfiles"
fi

open -a Zed "$ROOT"
