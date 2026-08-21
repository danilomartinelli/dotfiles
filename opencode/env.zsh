# shellcheck shell=bash

# Dotfiles-owned components and OpenCode configuration share one portable home.
# Migrate the previous XDG default on reload while preserving an explicit
# machine-local profile override.
case "${OPENCODE_CONFIG_DIR:-}" in
"" | "${XDG_CONFIG_HOME:-$HOME/.config}/opencode")
  export OPENCODE_CONFIG_DIR="$HOME/.opencode"
  ;;
esac

export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
export OPENCODE_EXPERIMENTAL_WORKSPACES=true
export OPENCODE_DISABLE_PROJECT_CONFIG=true
export OPENCODE_DISABLE_EXTERNAL_SKILLS=true
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=true

# cursor-acp is quarantined from the managed runtime. Clear values inherited
# from older shells so a stale provider process cannot retain the old bridge.
unset CURSOR_ACP_TOOL_LOOP_MODE
unset CURSOR_ACP_ENABLE_OPENCODE_TOOLS
unset CURSOR_ACP_MCP_BRIDGE
