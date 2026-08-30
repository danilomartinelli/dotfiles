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
  signer_email=$(git config --global user.email 2>/dev/null || true)
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

installer_success "git configuration complete"
