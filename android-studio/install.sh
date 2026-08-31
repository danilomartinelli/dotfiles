#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "checking Android Emulator support"

if "$DOTFILES_ROOT/_scripts/mobile-setup" --check android; then
  installer_success "Android Emulator support ready"
else
  installer_warn "Android Emulator support is incomplete"
  installer_hint "Run: mobile-setup android"
fi
