#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Claude Code configuration"

# Claude Code writes this file itself (/model, /config, the bypass-mode
# prompt), so a change made there lands here as a diff to keep or discard, the
# way Zed's settings do. State such as ~/.claude.json stays machine-local.
installer_link_config --label "Claude Code settings" \
  "$TOPIC_DIR/settings.json" "$HOME/.claude/settings.json"

# settings.json names this path in its hooks: a hook command is one string
# Claude Code hands to sh, with no way to ask where the checkout is.
installer_link_config --label "Impeccable hook gate" \
  "$TOPIC_DIR/impeccable-hook.sh" "$HOME/.claude/impeccable-hook.sh"

installer_success "Claude Code configured"
