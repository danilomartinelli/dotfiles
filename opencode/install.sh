#!/bin/sh

set -e

echo "› setting up OpenCode configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

mkdir -p "$CONFIG_DIR/skills" "$CONFIG_DIR/plugins" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands"

link_path() {
  source_path=$1
  target_path=$2
  label=$3

  if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
    echo "  ✓ $label already linked"
    return 0
  fi

  if [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
    backup="${target_path}.backup"
    if [ -e "$backup" ]; then
      echo "Warning: $target_path and $backup exist; leaving $label untouched" >&2
      return 0
    fi
    mv "$target_path" "$backup"
    echo "  → Existing $label moved to $backup"
  fi

  ln -sfn "$source_path" "$target_path"
  echo "  ✓ $label linked"
}

link_path "$TOPIC_DIR/opencode.json" "$CONFIG_DIR/opencode.json" "OpenCode config"

# Link each skill directory so new skills can be added in-repo.
for skill_dir in "$TOPIC_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  link_path "$skill_dir" "$CONFIG_DIR/skills/$skill_name" "skill $skill_name"
done

if command -v opencode >/dev/null 2>&1; then
  echo "  ✓ opencode CLI available"
else
  echo "  → Install OpenCode with: brew install opencode"
fi

echo "  → Put provider API keys in ~/.localrc (see .localrc.example)"
echo "  → Select a model in OpenCode with /models (Zen/Go, Kimi, MiniMax, Z.AI/GLM)"
echo "✓ OpenCode configured"
