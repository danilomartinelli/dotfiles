#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Update Dotfiles
# @raycast.mode silent
# @raycast.packageName Dotfiles
# @raycast.icon 🔄
# @raycast.description Run dot in a Ghostty window that stays open when it ends

set -euo pipefail

ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/../.." && pwd)

# dot asks questions and reports what it changed, so it runs where it can be
# watched and answered, and the window waits to be read afterwards.
open -na Ghostty.app --args --wait-after-command=true -e "$ROOT/raycast/_update"
