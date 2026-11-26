#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Herdr configuration"

# Herdr rewrites most of ~/.config/herdr-app on every start, so the files are
# linked one by one and the directory stays its own. The Settings window writes
# settings.json, so a change made there lands here as a diff to keep or
# discard. Estro's installer merges shortcuts into the app's keys.json.
installer_link_tool_config herdr-app "Herdr settings" settings.json
installer_link_tool_config herdr-app "Herdr programs" programs.json
installer_link_tool_config herdr-app "Herdr subagent hook" subagent-hook
installer_link_config --policy preserve-existing --label "Codex subagent hooks" \
  "$TOPIC_DIR/codex-hooks.json" "$HOME/.codex/hooks.json"

# The palette every other tool here uses, which Herdr does not ship.
# settings.json names it for both appearances.
installer_link_tool_config herdr-app "Herdr theme" themes/catppuccin-macchiato.json
installer_link_config --remove-owned --label "Herdr light theme" \
  "$TOPIC_DIR/themes/catppuccin-latte.json" \
  "$(installer_config_dir herdr-app)/themes/catppuccin-latte.json"

sh "$TOPIC_DIR/_install-estro.sh"

installer_success "Herdr configured"
