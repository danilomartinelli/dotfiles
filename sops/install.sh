#!/bin/sh

set -eu

echo "› setting up sops configuration"

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
age_dir=$config_home/sops/age
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

if [ -f "$default_key" ]; then
  echo "  → default age identity already present"
  if [ -f "$default_recipient" ]; then
    echo "  → recipient: $(cat "$default_recipient")"
  fi
else
  echo "  → no default age identity yet"
  echo "  Create one with: sops-key-create default"
fi

echo "✓ sops configuration complete"
