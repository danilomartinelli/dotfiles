#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenCode configuration"

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

mkdir -p "$CONFIG_DIR/skills" "$CONFIG_DIR/plugins" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands"

# Render the portable template directly instead of linking and then replacing
# the link. `skills.paths` and `instructions` resolve relative to opencode's
# cwd, so __DOTFILES_ROOT__ must become an absolute path. Comparing first keeps
# repeated installs idempotent; a changed target is preserved in a numbered
# backup before the new render replaces it.
CONFIG_SOURCE="$TOPIC_DIR/opencode.json"
CONFIG_TARGET="$CONFIG_DIR/opencode.json"
rendered=$(mktemp "$CONFIG_DIR/.opencode.json.XXXXXX")
if ! sed "s|__DOTFILES_ROOT__|$DOTFILES_ROOT|g" "$CONFIG_SOURCE" >"$rendered"; then
  rm -f "$rendered"
  exit 1
fi

if cmp -s "$rendered" "$CONFIG_TARGET"; then
  rm "$rendered"
  installer_success "OpenCode config already rendered"
else
  if [ -e "$CONFIG_TARGET" ] || [ -L "$CONFIG_TARGET" ]; then
    backup="$CONFIG_TARGET.backup"
    backup_number=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="$CONFIG_TARGET.backup.$backup_number"
      backup_number=$((backup_number + 1))
    done
    mv "$CONFIG_TARGET" "$backup"
    installer_note "Existing OpenCode config moved to $backup"
  fi
  mv "$rendered" "$CONFIG_TARGET"
  installer_success "OpenCode config rendered"
fi

installer_link_config --label "OpenCode TUI config" \
  "$TOPIC_DIR/tui.json" "$CONFIG_DIR/tui.json"

# Link each skill directory so new skills can be added in-repo.
for skill_dir in "$TOPIC_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_dir=${skill_dir%/}
  skill_name=$(basename "$skill_dir")
  installer_link_config --label "skill $skill_name" \
    "$skill_dir" "$CONFIG_DIR/skills/$skill_name"
done

# OCX (https://github.com/kdcokenny/ocx) is the OpenCode extension manager.
if command -v ocx >/dev/null 2>&1; then
  installer_success "ocx CLI available"

  # The link helper owns the target path; creating ~/.opencode first would
  # force every fresh install through the backup path.
  installer_link_config --policy numbered-backup --label "OpenCode OCX config" \
    "$TOPIC_DIR/extensions" "$HOME/.opencode"

  installer_note "Launch OpenCode with a profile via: ocx oc -p <profile>"
else
  installer_note "Install OCX with: mise install"
fi

# Install the opencode CLI if unavailable.
if command -v opencode >/dev/null 2>&1; then
  installer_success "opencode CLI available"
else
  installer_note "Install OpenCode with: brew install opencode"
fi

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Select a model in OpenCode with /models (Zen/Go, Kimi, MiniMax, Z.AI/GLM)"
installer_success "OpenCode configured"
