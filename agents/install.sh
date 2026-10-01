#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up global agent instructions"

# One file, read under each agent's own name and from each agent's own
# directory. The directories are the tools' contracts, not ours: see
# docs/adr/0003-tool-config-directories-are-not-xdg-derived.md.
link_instructions() {
  mkdir -p "$(dirname -- "$2")"
  installer_link_config --label "$1 instructions" \
    "$TOPIC_DIR/instructions.md" "$2"
}

link_instructions "Claude Code" "$HOME/.claude/CLAUDE.md"
link_instructions Codex "$HOME/.codex/AGENTS.md"
link_instructions "Kimi Code" "$HOME/.agents/AGENTS.md"
link_instructions OpenCode "$(installer_config_dir opencode)/AGENTS.md"

installer_success "Global agent instructions configured"
