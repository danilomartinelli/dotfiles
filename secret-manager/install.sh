#!/bin/sh

if ! command -v bws >/dev/null 2>&1
then
  curl https://bws.bitwarden.com/install | sh
fi

echo "✓ Bitwarden CLI installed"
