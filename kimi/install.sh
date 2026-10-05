#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Kimi Code configuration"

# Only the terminal settings are linked. config.toml carries provider
# credentials and is rewritten by every login, so it stays machine-local.
installer_link_config --label "Kimi Code TUI settings" \
  "$TOPIC_DIR/tui.toml" "$HOME/.kimi-code/tui.toml"

installer_success "Kimi Code configured"
