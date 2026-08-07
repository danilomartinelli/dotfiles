#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenCode configuration"

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

mkdir -p "$CONFIG_DIR/skills" "$CONFIG_DIR/plugins" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands"

installer_link_config --label "OpenCode config" \
  "$TOPIC_DIR/opencode.json" "$CONFIG_DIR/opencode.json"

installer_link_config --label "OpenCode TUI config" \
  "$TOPIC_DIR/tui.json" "$CONFIG_DIR/tui.json"

installer_link_config --label "oh-my-opencode-slim config" \
  "$TOPIC_DIR/oh-my-opencode-slim.json" "$CONFIG_DIR/oh-my-opencode-slim.json"

# Link each skill directory so new skills can be added in-repo.
for skill_dir in "$TOPIC_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_dir=${skill_dir%/}
  skill_name=$(basename "$skill_dir")
  installer_link_config --label "skill $skill_name" \
    "$skill_dir" "$CONFIG_DIR/skills/$skill_name"
done

if command -v opencode >/dev/null 2>&1; then
  installer_success "opencode CLI available"
else
  installer_note "Install OpenCode with: brew install opencode"
fi

# Suppress the codex chronicle feature warning if the config file already exists.
# If the file does not exist yet, codex will create it on first run.
CODEX_CONFIG="$HOME/.codex/config.toml"
if [ -f "$CODEX_CONFIG" ] && ! grep -q "suppress_unstable_features_warning" "$CODEX_CONFIG"; then
  # Prepend the key to suppress the chronicle feature warning.
  tmp=$(mktemp)
  {
    printf 'suppress_unstable_features_warning = true\n\n'
    cat "$CODEX_CONFIG"
  } >"$tmp"
  mv "$tmp" "$CODEX_CONFIG"
  installer_success "Suppressed codex unstable features warning in $CODEX_CONFIG"
fi

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Select a model in OpenCode with /models (Zen/Go, Kimi, MiniMax, Z.AI/GLM)"
installer_success "OpenCode configured"
