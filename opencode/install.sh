#!/bin/sh

set -e

echo "› setting up OpenCode configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
DOTFILES_ROOT=$(CDPATH='' cd -P -- "$TOPIC_DIR/.." && pwd)
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
LINK_CONFIG="$DOTFILES_ROOT/_scripts/link-config"

mkdir -p "$CONFIG_DIR/skills" "$CONFIG_DIR/plugins" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands"

"$LINK_CONFIG" --label "OpenCode config" \
  "$TOPIC_DIR/opencode.json" "$CONFIG_DIR/opencode.json"

# Link each skill directory so new skills can be added in-repo.
for skill_dir in "$TOPIC_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_dir=${skill_dir%/}
  skill_name=$(basename "$skill_dir")
  "$LINK_CONFIG" --label "skill $skill_name" \
    "$skill_dir" "$CONFIG_DIR/skills/$skill_name"
done

if command -v opencode >/dev/null 2>&1; then
  echo "  ✓ opencode CLI available"
else
  echo "  → Install OpenCode with: brew install opencode"
fi

echo "  → Put provider API keys in ~/.localrc (see .localrc.example)"
echo "  → Select a model in OpenCode with /models (Zen/Go, Kimi, MiniMax, Z.AI/GLM)"
echo "✓ OpenCode configured"
