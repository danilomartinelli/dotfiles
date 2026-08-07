#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenCode configuration"

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
SHARED_SKILLS_DIR="$DOTFILES_ROOT/_shared/agents/skills"
SHARED_AGENTS_MD="$DOTFILES_ROOT/_shared/agents/AGENTS.md"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

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

installer_link_config --label "oh-my-opencode-slim config" \
  "$TOPIC_DIR/oh-my-opencode-slim.json" "$CONFIG_DIR/oh-my-opencode-slim.json"

# Link the oh-my-opencode-slim prompt overrides. The plugin looks here for
# {preset}/{agent}.md and {preset}/{agent}_append.md files; without this link
# the orchestrator_append.md that injects the shared agents philosophy never
# reaches the running session.
if [ -d "$TOPIC_DIR/oh-my-opencode-slim" ]; then
  installer_link_config --label "oh-my-opencode-slim prompt overrides" \
    "$TOPIC_DIR/oh-my-opencode-slim" "$CONFIG_DIR/oh-my-opencode-slim"
fi

# Link each skill directory so new skills can be added in-repo.
for skill_dir in "$TOPIC_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_dir=${skill_dir%/}
  skill_name=$(basename "$skill_dir")
  installer_link_config --label "skill $skill_name" \
    "$skill_dir" "$CONFIG_DIR/skills/$skill_name"
done

# Surface the shared PM skills library to OpenCode as well. We append the path
# to skills.paths (rather than copying) so the orchestrator can route to any of
# them and the source of truth stays in _shared/agents/skills. The library is
# description-gated, so it does not pre-load into every turn's context.
if [ -d "$SHARED_SKILLS_DIR" ]; then
  installer_note "Shared PM skills library at $SHARED_SKILLS_DIR"
  installer_note "Add it to ~/.config/opencode/opencode.json under skills.paths to expose"
  installer_note "Example: \"skills\": { \"paths\": [\"$SHARED_SKILLS_DIR\"] }"
fi

# Same library is consumed by ChatGPT Desktop / Codex. Codex's own skills
# directory may already hold its bundled skills (e.g. chronicle), so we add
# individual symlinks rather than replace the directory. Each Codex symlink
# points at a single skill folder and uses `ln -sfn` so a subsequent install
# is a no-op when the target is already correct.
if [ -d "$SHARED_SKILLS_DIR" ]; then
  mkdir -p "$CODEX_HOME/skills"
  linked=0
  skipped=0
  for skill_dir in "$SHARED_SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_dir=${skill_dir%/}
    skill_name=$(basename "$skill_dir")
    target="$CODEX_HOME/skills/$skill_name"
    source_canonical=$(CDPATH='' cd -P -- "$skill_dir" && pwd)
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source_canonical" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    ln -sfn "$source_canonical" "$target"
    linked=$((linked + 1))
  done
  installer_success "Codex skills: $linked linked, $skipped already current in $CODEX_HOME/skills"
fi

# Codex reads ~/.codex/AGENTS.md as the global instructions file. Symlink the
# shared agents contract so the same operating philosophy applies across both
# agents (orchestrator in opencode, system rule in Codex).
if [ -f "$SHARED_AGENTS_MD" ] && [ ! -e "$CODEX_HOME/AGENTS.md" ]; then
  ln -s "$SHARED_AGENTS_MD" "$CODEX_HOME/AGENTS.md"
  installer_success "Linked $CODEX_HOME/AGENTS.md -> $SHARED_AGENTS_MD"
elif [ -f "$SHARED_AGENTS_MD" ] && [ -L "$CODEX_HOME/AGENTS.md" ]; then
  installer_note "$CODEX_HOME/AGENTS.md already a symlink"
elif [ -f "$SHARED_AGENTS_MD" ]; then
  installer_warn "$CODEX_HOME/AGENTS.md exists and is not a symlink"
  installer_hint "Replace it with: ln -sfn '$SHARED_AGENTS_MD' '$CODEX_HOME/AGENTS.md'"
fi

if command -v opencode >/dev/null 2>&1; then
  installer_success "opencode CLI available"
else
  installer_note "Install OpenCode with: brew install opencode"
fi

# Suppress the codex chronicle feature warning if the config file already exists.
# If the file does not exist yet, codex will create it on first run.
CODEX_CONFIG="$CODEX_HOME/config.toml"
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
