#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Project
# @raycast.mode silent
# @raycast.packageName Dotfiles
# @raycast.icon 📁
# @raycast.argument1 { "type": "text", "placeholder": "project" }
# @raycast.description Open the best-matching project under $PROJECTS in Zed

set -euo pipefail

ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/../.." && pwd)
# shellcheck source=raycast/_project.sh
# shellcheck disable=SC1091
. "$ROOT/raycast/_project.sh"

if ! project=$(project_find "${1:-}"); then
  echo "No project matches '${1:-}'"
  exit 1
fi

open -a Zed "$project"
echo "Opened ${project##*/}"
