#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Block Goose configuration"

CONFIG_DIR="$HOME/.config/goose"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

mkdir -p "$CONFIG_DIR"

# Goose reaches Claude Code and Codex through ACP *providers*, not extensions.
# Extensions of type stdio are MCP servers, so an ACP agent binary registered
# there never initializes. See https://goose-docs.ai/docs/guides/acp-providers
if command -v yq >/dev/null 2>&1; then
  if [ ! -f "$CONFIG_FILE" ]; then
    printf '' >"$CONFIG_FILE"
    installer_note "Created empty $CONFIG_FILE"
  fi
  yq -i '
      del(.active_provider | select(. == ""))
    | .providers."claude-acp".enabled = true
    | .providers."claude-acp".configured = true
    | .providers."claude-acp".model = (.providers."claude-acp".model // "default")
    | .providers."claude-acp".model |= (select(. == "current") = "default")
    | .providers."codex-acp".enabled = true
    | .providers."codex-acp".configured = true
    | .providers."codex-acp".model = (.providers."codex-acp".model // "current")
    | .active_provider = (.active_provider // "claude-acp")
    | del(.GOOSE_PROVIDER, .GOOSE_MODEL, .["claude-acp_configured"])
    | del(.extensions."codex-acp", .extensions."claude-acp")
  ' "$CONFIG_FILE"
  installer_success "Registered claude-acp and codex-acp providers in $CONFIG_FILE"
else
  installer_link_config --policy preserve-existing --label "Goose config.yaml" \
    "$TOPIC_DIR/config.yaml" "$CONFIG_FILE"
fi

# ACP providers shell out to their adapter binary, so a missing adapter only
# fails once a session starts. Warn early instead of failing the update.
for adapter in claude-agent-acp codex-acp; do
  if ! command -v "$adapter" >/dev/null 2>&1; then
    installer_warn "ACP adapter $adapter not found on PATH"
    installer_hint "run 'mise install' to provision @agentclientprotocol/$adapter"
  fi
done

installer_note "Pick the active provider in Goose Desktop under Settings > Models"
installer_success "Block Goose configured"
