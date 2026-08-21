# shellcheck shell=bash

# OCX-managed components and OpenCode configuration share one portable home.
# Migrate the previous XDG default on reload, while preserving a machine-local
# or OCX profile override.
case "${OPENCODE_CONFIG_DIR:-}" in
"" | "${XDG_CONFIG_HOME:-$HOME/.config}/opencode")
  export OPENCODE_CONFIG_DIR="$HOME/.opencode"
  ;;
esac

export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
export OPENCODE_EXPERIMENTAL_WORKSPACES=true

# Cursor supplies models through open-cursor, but OpenCode remains responsible
# for tool discovery, permissions, execution, and MCP integration.
export CURSOR_ACP_TOOL_LOOP_MODE=opencode
export CURSOR_ACP_ENABLE_OPENCODE_TOOLS=true
