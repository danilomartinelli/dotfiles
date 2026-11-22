#!/bin/sh

set -eu

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up git configuration"

config_dir=$(installer_config_dir git)
allowed_signers=$config_dir/allowed_signers
default_key=$HOME/.ssh/id_ed25519.pub

mkdir -p "$config_dir"

# Populate allowed_signers from the default signing key so `git log
# --show-signature` verifies locally. Never creates or rotates keys.
if [ -f "$default_key" ]; then
  # The identity lives in the file the tracked gitconfig includes, and a
  # query of one file follows its includes only when asked to.
  signer_email=$(git config --global --includes user.email 2>/dev/null || true)
  if [ -n "$signer_email" ]; then
    signer_line="$signer_email $(cat "$default_key")"
    if [ -f "$allowed_signers" ] && grep -qF "$(cat "$default_key")" "$allowed_signers"; then
      installer_note "default signing key already in allowed_signers"
    else
      printf '%s\n' "$signer_line" >>"$allowed_signers"
      installer_success "registered default key in allowed_signers"
    fi
  else
    installer_note "git user.email not set yet; skipping allowed_signers"
  fi
else
  installer_note "no default SSH key yet; enable signing after ssh-key-create default"
fi

# Sign commits and tags with the default key. The settings go in the
# machine-local file because they name a key only this machine has, and a value
# already there is the owner's and is left alone, including an explicit false.
local_config=$HOME/.gitconfig.local
enable_signing_setting() {
  if git config --file "$local_config" --get "$1" >/dev/null 2>&1; then
    return 0
  fi
  git config --file "$local_config" "$1" "$2"
  installer_item "set $1 in the machine-local Git configuration"
}

if [ ! -f "$default_key" ]; then
  :
elif [ ! -e "$local_config" ]; then
  installer_note "the machine-local Git configuration does not exist yet; signing not enabled"
else
  enable_signing_setting user.signingkey "$default_key"
  enable_signing_setting commit.gpgsign true
  enable_signing_setting tag.gpgsign true
fi

# core.hooksPath in the tracked gitconfig names this directory.
installer_link_tool_config git "Git hooks" hooks

installer_success "git configuration complete"
