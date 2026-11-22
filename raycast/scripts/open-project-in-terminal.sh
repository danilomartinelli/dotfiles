#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Project in Terminal
# @raycast.mode silent
# @raycast.packageName Dotfiles
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "text", "placeholder": "project" }
# @raycast.description Open a Ghostty window in the best-matching project under $PROJECTS

set -euo pipefail

ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/../.." && pwd)
# shellcheck source=raycast/_project.sh
# shellcheck disable=SC1091
. "$ROOT/raycast/_project.sh"

if ! project=$(project_find "${1:-}"); then
  echo "No project matches '${1:-}'"
  exit 1
fi

# Ghostty has no command of its own for a new window on macOS; this is the
# form its help gives.
open -na Ghostty.app --args --working-directory="$project"
echo "Opened ${project##*/}"
