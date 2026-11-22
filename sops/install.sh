#!/bin/sh

set -eu

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up sops configuration"

age_dir=$(installer_config_dir sops)/age
default_key=$age_dir/keys.txt
default_recipient=$age_dir/recipient.txt

umask 077
mkdir -p "$age_dir"
chmod 700 "$age_dir"

# Repair permissions on existing identities without creating or rotating them.
for key_file in "$age_dir"/keys*.txt; do
  [ -f "$key_file" ] || continue
  chmod 600 "$key_file"
done

for recipient_file in "$age_dir"/recipient*.txt; do
  [ -f "$recipient_file" ] || continue
  chmod 644 "$recipient_file"
done

# The recipient is the identity's public half, so a missing one is derived
# rather than left for a person to reconstruct. Nothing here creates a key.
if [ -f "$default_key" ] && [ ! -f "$default_recipient" ] \
  && command -v age-keygen >/dev/null 2>&1; then
  if age-keygen -y "$default_key" >"$default_recipient" 2>/dev/null; then
    chmod 644 "$default_recipient"
    installer_item "derived the default recipient from the identity"
  else
    rm -f -- "$default_recipient"
    installer_warn "could not derive a recipient from $default_key"
  fi
fi

if [ -f "$default_key" ]; then
  installer_note "default age identity already present"
  installer_note "back up $default_key somewhere safe: losing it loses every secret encrypted to it"
  if [ -f "$default_recipient" ]; then
    installer_note "recipient: $(cat "$default_recipient")"
  fi
else
  installer_note "no default age identity yet"
  installer_note "create one with: sops-key-create default"
fi

installer_success "sops configuration complete"
