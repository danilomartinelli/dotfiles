#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenCode configuration"

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

mkdir -p "$CONFIG_DIR/skills" "$CONFIG_DIR/plugins" "$CONFIG_DIR/agents" "$CONFIG_DIR/commands"

installer_link_config --label "OpenCode config" \
  "$TOPIC_DIR/opencode.json" "$CONFIG_DIR/opencode.json"

# Resolve __DOTFILES_ROOT__ placeholders in the opencode config copy. The
# link above is a symlink, so we replace it with a real file at the target
# path. `skills.paths` and `instructions` resolve relative to opencode's cwd,
# not the config file, so the value has to be an absolute path. We keep the
# placeholder in the repo so the file stays portable across machines; the
# installer is the only place that knows the real $HOME.
if [ -L "$CONFIG_DIR/opencode.json" ] && grep -q '__DOTFILES_ROOT__' "$CONFIG_DIR/opencode.json"; then
  rendered=$(mktemp)
  sed "s|__DOTFILES_ROOT__|$DOTFILES_ROOT|g" "$CONFIG_DIR/opencode.json" >"$rendered"
  rm "$CONFIG_DIR/opencode.json"
  mv "$rendered" "$CONFIG_DIR/opencode.json"
  installer_success "Rendered __DOTFILES_ROOT__ in $CONFIG_DIR/opencode.json"
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
# `init --global` is create-if-missing and will not overwrite opencode.json.
if command -v ocx >/dev/null 2>&1; then
  installer_success "ocx CLI available"
  if ocx init --global --quiet; then
    installer_success "OCX global config initialized"
  else
    installer_warn "ocx init --global failed"
  fi
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
