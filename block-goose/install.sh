#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Block Goose configuration"

CONFIG_DIR="$HOME/.config/goose"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

mkdir -p "$CONFIG_DIR"

if command -v yq >/dev/null 2>&1; then
  if [ ! -f "$CONFIG_FILE" ]; then
    printf '' >"$CONFIG_FILE"
    installer_note "Created empty $CONFIG_FILE"
  fi
  # Merge provider keys (idempotent).
  yq -i \
    '.GOOSE_PROVIDER = "claude-acp" | .GOOSE_MODEL = "current" | .["claude-acp_configured"] = true' \
    "$CONFIG_FILE"
  # Merge codex-acp extension without clobbering existing extensions.
  yq -i \
    '.extensions.codex-acp.enabled = true
     | .extensions.codex-acp.type = "stdio"
     | .extensions.codex-acp.name = "codex-acp"
     | .extensions.codex-acp.cmd = "codex-acp"
     | .extensions.codex-acp.args = []
     | .extensions.codex-acp.description = "OpenAI Codex via ACP for code generation and editing"' \
    "$CONFIG_FILE"
  installer_success "Merged provider and codex-acp extension into $CONFIG_FILE"
else
  installer_link_config --policy preserve-existing --label "Goose config.yaml" \
    "$TOPIC_DIR/config.yaml" "$CONFIG_FILE"
fi

installer_note "Open Goose once to verify the claude-acp provider and codex-acp extension"
installer_success "Block Goose configured"
