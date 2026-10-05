#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Dotfiles
# @raycast.mode silent
# @raycast.packageName Dotfiles
# @raycast.icon 📂
# @raycast.description Open the active dotfiles checkout in $EDITOR

set -euo pipefail

# Open the checkout containing this script: raycast/scripts/ is two levels
# below the root.
ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/../.." && pwd)

open -a Zed "$ROOT"
