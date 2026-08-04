#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Dotfiles
# @raycast.mode silent
# @raycast.packageName Dotfiles
# @raycast.icon 📂
# @raycast.description Open the active dotfiles checkout in $EDITOR

set -euo pipefail

# Resolve the checkout from this script's location (raycast/scripts/ is two
# levels below the root), falling back to the stable home link.
ROOT="${DOTFILES_ROOT:-}"
if [ -z "$ROOT" ]; then
  ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/../.." && pwd)
fi
if [ ! -f "$ROOT/dotfiles-root.symlink" ] && [ -L "$HOME/.dotfiles-root" ]; then
  ROOT=$(readlink "$HOME/.dotfiles-root")
fi

open -a Zed "$ROOT"
