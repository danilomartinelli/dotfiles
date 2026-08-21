#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenCode"

DEFAULT_CONFIG_DIR="$HOME/.opencode"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
LEGACY_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

if [ "$CONFIG_DIR" = "$LEGACY_CONFIG_DIR" ]; then
  CONFIG_DIR=$DEFAULT_CONFIG_DIR
fi

legacy_config_has_policy_overlay() {
  [ -d "$LEGACY_CONFIG_DIR" ] || return 1

  for legacy_entry in \
    "$LEGACY_CONFIG_DIR"/* \
    "$LEGACY_CONFIG_DIR"/.[!.]* \
    "$LEGACY_CONFIG_DIR"/..?*; do
    [ -e "$legacy_entry" ] || [ -L "$legacy_entry" ] || continue
    legacy_name=${legacy_entry##*/}

    case "$legacy_name" in
      node_modules | logs)
        [ -d "$legacy_entry" ] && [ ! -L "$legacy_entry" ] || return 0
        ;;
      plugin | skills)
        [ -d "$legacy_entry" ] && [ ! -L "$legacy_entry" ] || return 0
        if [ -n "$(find "$legacy_entry" -mindepth 1 -print -quit 2>/dev/null)" ]; then
          return 0
        fi
        ;;
      package-lock.json | bun.lock | .gitignore)
        [ -f "$legacy_entry" ] && [ ! -L "$legacy_entry" ] || return 0
        ;;
      package.json)
        [ -f "$legacy_entry" ] && [ ! -L "$legacy_entry" ] || return 0
        legacy_compact=$(tr -d '[:space:]' <"$legacy_entry")
        printf '%s\n' "$legacy_compact" \
          | grep -Eq '^\{"dependencies":\{"@opencode-ai/plugin":"[0-9]+\.[0-9]+\.[0-9]+"\}\}$' \
          || return 0
        ;;
      dcp.json | dcp.jsonc)
        [ -f "$legacy_entry" ] && [ ! -L "$legacy_entry" ] || return 0
        legacy_compact=$(tr -d '[:space:]' <"$legacy_entry")
        # The dollar sign is part of the JSON Schema key, not a shell expansion.
        # shellcheck disable=SC2016
        printf '%s\n' "$legacy_compact" \
          | grep -Eq '^\{"\$schema":"https://raw\.githubusercontent\.com/Opencode-DCP/opencode-dynamic-context-pruning/master/dcp\.schema\.json",?\}$' \
          || return 0
        ;;
      *)
        return 0
        ;;
    esac
  done

  return 1
}

canonical_entry_path() {
  entry_path=$1
  entry_dir=$(CDPATH='' cd -P -- "$(dirname -- "$entry_path")" 2>/dev/null && pwd) \
    || return 1
  printf '%s/%s\n' "$entry_dir" "$(basename -- "$entry_path")"
}

default_config_is_linked() {
  [ -L "$DEFAULT_CONFIG_DIR" ] || return 1

  config_target=$(readlink "$DEFAULT_CONFIG_DIR") || return 1
  case "$config_target" in
    /*) ;;
    *) config_target=$(dirname -- "$DEFAULT_CONFIG_DIR")/$config_target ;;
  esac

  config_target=$(canonical_entry_path "$config_target") || return 1
  managed_target=$(canonical_entry_path "$TOPIC_DIR/opencode.symlink") || return 1
  [ "$config_target" = "$managed_target" ]
}

# OpenCode keeps generated package support in its conventional XDG directory
# even when OPENCODE_CONFIG_DIR points at the managed payload. Permit only that
# known cache shape plus an empty DCP bootstrap file; policy-bearing config,
# plugins, and skills still fail closed because OpenCode merges them.
if [ "$LEGACY_CONFIG_DIR" != "$DEFAULT_CONFIG_DIR" ] && legacy_config_has_policy_overlay; then
  installer_error "Legacy OpenCode config can shadow the managed payload: $LEGACY_CONFIG_DIR"
  installer_hint "Archive policy files, plugins, and skills from that directory, then rerun setup; ~/.opencode is the only supported policy root"
  exit 1
fi

# Bootstrap owns *.symlink entries. The installer only verifies that the
# OpenCode payload is available; duplicating link ownership here would make
# conflict handling differ between first install and subsequent updates.
if [ "$CONFIG_DIR" = "$DEFAULT_CONFIG_DIR" ] && default_config_is_linked; then
  installer_success "OpenCode config available at $CONFIG_DIR"
elif [ "$CONFIG_DIR" != "$DEFAULT_CONFIG_DIR" ] && [ -d "$CONFIG_DIR" ]; then
  installer_success "OpenCode config available at $CONFIG_DIR"
else
  installer_error "OpenCode config is not linked at $CONFIG_DIR"
  installer_hint "Run $DOTFILES_ROOT/_scripts/link-dotfiles to link opencode/opencode.symlink"
  exit 1
fi

# The managed payload is versioned and customized by dotfiles. An OCX receipt
# that also claims files below ~/.opencode creates two writers and can overwrite
# the orchestration boundary during `ocx update`, so reject that state.
OCX_RECEIPT="$HOME/.ocx/receipt.jsonc"
if [ -f "$OCX_RECEIPT" ] \
  && grep -Eq '"path"[[:space:]]*:[[:space:]]*"\.?/?\.opencode/' "$OCX_RECEIPT"; then
  installer_error "OCX receipt also claims the dotfiles-owned ~/.opencode payload: $OCX_RECEIPT"
  installer_hint "Archive the receipt and reinstall only components outside ~/.opencode"
  exit 1
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

installer_note "cursor-acp is quarantined: provider-native effects cannot be gated by OpenCode permissions or managed worktrees"

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Select a model in OpenCode with /models"
installer_success "OpenCode configured"
