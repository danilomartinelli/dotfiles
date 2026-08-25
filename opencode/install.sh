#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up OpenCode configuration"

CONFIG_DIR="$HOME/.config/opencode"

mkdir -p "$CONFIG_DIR"

installer_require_command opencode

installer_require_command ocx

ocx init --global
ocx registry add https://registry.kdco.dev --name kdco --global

OCX_RECEIPT="$CONFIG_DIR/.ocx/receipt.jsonc"
if [ -f "$OCX_RECEIPT" ] && grep -Fq '::kdco/workspace@' "$OCX_RECEIPT"; then
  installer_note "OCX workspace already installed"
else
  ocx add kdco/workspace --global
fi

configure_managed_entry() {
  entry_name=$1
  entry_source="$TOPIC_DIR/$entry_name"
  entry_target="$CONFIG_DIR/$entry_name"

  if [ ! -e "$entry_source" ]; then
    installer_error "OpenCode config source not found: $entry_source"
    exit 1
  fi

  # OCX owns installation and updates; dotfiles owns the editable result.
  # Runtime-only entries such as plugins, .ocx and package.json stay untouched.
  rm -rf "$entry_target"
  installer_link_config \
    --label "OpenCode $entry_name" \
    "$entry_source" "$entry_target"
}

configure_profile() {
  profile_name=$1
  profile_source="$TOPIC_DIR/profiles/$profile_name"
  profile_target="$CONFIG_DIR/profiles/$profile_name"

  if [ ! -d "$profile_source" ]; then
    installer_error "OpenCode profile source not found: $profile_source"
    exit 1
  fi

  ocx profile remove "$profile_name" --global
  ocx profile add "$profile_name" --global

  # OCX creates a profile directory. Replace that generated directory with the
  # repository-owned profile so edits remain versioned in dotfiles.
  rm -rf "$profile_target"
  installer_link_config \
    --label "OpenCode $profile_name profile" \
    "$profile_source" "$profile_target"
}

configure_managed_entry agents
configure_managed_entry commands
configure_managed_entry skills
configure_managed_entry tools
configure_managed_entry ocx.jsonc
configure_managed_entry opencode.jsonc
configure_managed_entry tui.jsonc

configure_profile boost
configure_profile regular
configure_profile go

installer_success "OpenCode configured"
