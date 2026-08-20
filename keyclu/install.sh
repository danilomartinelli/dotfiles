#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring KeyClu"

installer_require_app KeyClu keyclu "/Applications/KeyClu.app"

# No `defaults write` here: launch-at-login is SMAppService territory on
# modern macOS and the app persists its own preferences on quit.
SHORTCUTS_FILE="$TOPIC_DIR/custom-shortcuts.keyclu"
if [ -f "$SHORTCUTS_FILE" ]; then
  if [ -t 1 ]; then
    installer_note "Custom shortcuts versioned at $SHORTCUTS_FILE"
    installer_note "Run 'keyclu-import' (or press ⌘ twice and use Settings -> My Shortcuts -> Import) to load them"
  fi
fi

installer_success "KeyClu ready — hold ⌘ to browse app shortcuts, or run 'keyclu-import' to load the dotfiles cheatsheet"
installer_success "KeyClu configured"
