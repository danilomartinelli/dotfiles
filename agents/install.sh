#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up global agent instructions"

# One file, read under each agent's own name and from each agent's own
# directory. The directories are the tools' contracts, not ours.
link_instructions() {
  installer_link_config --label "$1 instructions" \
    "$TOPIC_DIR/instructions.md" "$2"
}

link_instructions "Claude Code" "$HOME/.claude/CLAUDE.md"
link_instructions Codex "$HOME/.codex/AGENTS.md"
link_instructions OpenCode "$(installer_config_dir opencode)/AGENTS.md"
link_instructions Antigravity "$HOME/.gemini/AGENTS.md"

# Kimi Code read the instructions from here before it was removed.
installer_link_config --remove-owned --label "Kimi Code instructions" \
  "$TOPIC_DIR/instructions.md" "$HOME/.agents/AGENTS.md"

# The MCP servers of the agents whose configuration is machine-local. The
# tracked Zed and OpenCode files are rendered from the same catalog.
"$DOTFILES_ROOT/_scripts/mcp-servers" apply

installer_success "Global agent instructions configured"
