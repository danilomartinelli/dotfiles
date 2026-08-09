#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Hermes Agent"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SHARED_SKILLS_DIR="$DOTFILES_ROOT/_shared/agents/skills"
HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-anthropic/claude-opus-5}"

mkdir -p "$HERMES_HOME"

if ! command -v hermes >/dev/null 2>&1; then
  installer_note "Install Hermes with: brew install hermes-agent"
  installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
  installer_success "Hermes Agent configured"
  exit 0
fi

installer_success "hermes CLI available"

# Hermes reads skills from $HERMES_HOME/skills/<name>/SKILL.md using the same
# frontmatter (name + description) as Claude Code, Codex and OpenCode — the
# shared library needs no conversion. `hermes skills config` exposes no
# configurable search path, so the directory is fixed and we link into it.
#
# Skills installed from Hermes' own registry (the Cloudflare set, for
# example) are real directories living alongside these symlinks. Only
# symlinks we own are refreshed; anything else is left untouched, so a
# registry-installed skill is never clobbered by an update.
if [ -d "$SHARED_SKILLS_DIR" ]; then
  mkdir -p "$HERMES_HOME/skills"
  linked=0
  skipped=0
  for skill_dir in "$SHARED_SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_dir=${skill_dir%/}
    skill_name=$(basename "$skill_dir")
    target="$HERMES_HOME/skills/$skill_name"
    source_canonical=$(CDPATH='' cd -P -- "$skill_dir" && pwd)

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source_canonical" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    # A real directory here came from `hermes skills install`; leave it be.
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    ln -sfn "$source_canonical" "$target"
    linked=$((linked + 1))
  done
  installer_success "Hermes skills: $linked linked, $skipped already present in $HERMES_HOME/skills"
fi

# Set a default model only when none is configured. Forcing it on every run
# would silently undo a model picked interactively with `hermes model`.
current_model=$(hermes config get model 2>/dev/null | tail -1 || true)
case "$current_model" in
  "" | *"not set"* | *"(auto)"*)
    hermes config set model "$HERMES_DEFAULT_MODEL" >/dev/null 2>&1 \
      && installer_success "Default model set to $HERMES_DEFAULT_MODEL"
    ;;
  *)
    installer_note "Model already set to $current_model"
    ;;
esac

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Change provider/model interactively with: hermes model"
installer_success "Hermes Agent configured"
