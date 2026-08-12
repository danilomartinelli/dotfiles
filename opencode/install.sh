#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenCode"

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.opencode}"

# Bootstrap owns *.symlink entries. The installer only verifies that the
# OpenCode payload is available; duplicating link ownership here would make
# conflict handling differ between first install and subsequent updates.
if [ -d "$CONFIG_DIR" ]; then
  installer_success "OpenCode config available at $CONFIG_DIR"
else
  installer_warn "OpenCode config is not linked at $CONFIG_DIR"
  installer_hint "Run $DOTFILES_ROOT/_scripts/link-dotfiles to link opencode/opencode.symlink"
fi

# OCX 2.0 receipts may store this registry instruction relative to the config
# directory even though the resolver interprets it relative to the workspace.
# Normalize only the known legacy value; the receipt otherwise remains owned
# by OCX and machine-local.
OCX_RECEIPT="$HOME/.ocx/receipt.jsonc"
if [ -f "$OCX_RECEIPT" ] && \
  grep -Fq '"./tools/philosophy.md"' "$OCX_RECEIPT"; then
  receipt_dir=$(dirname -- "$OCX_RECEIPT")
  rendered_receipt=$(mktemp "$receipt_dir/.receipt.jsonc.XXXXXX")
  if cp -p "$OCX_RECEIPT" "$rendered_receipt" && \
    sed 's|"\./tools/philosophy\.md"|".opencode/tools/philosophy.md"|g' \
      "$OCX_RECEIPT" >"$rendered_receipt" && \
    grep -Fq '".opencode/tools/philosophy.md"' "$rendered_receipt" && \
    mv "$rendered_receipt" "$OCX_RECEIPT"; then
    installer_success "Migrated OCX receipt instruction path"
  else
    rm -f "$rendered_receipt"
    installer_warn "Could not migrate $OCX_RECEIPT"
    installer_hint "Replace ./tools/philosophy.md with .opencode/tools/philosophy.md"
  fi
fi

if command -v ocx >/dev/null 2>&1; then
  installer_success "ocx CLI available"
else
  installer_note "Install OCX with: mise install"
fi

if command -v opencode >/dev/null 2>&1; then
  installer_success "opencode CLI available"
else
  installer_note "Install OpenCode with: mise install"
fi

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Select a model in OpenCode with /models"
installer_success "OpenCode configured"
