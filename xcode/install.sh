#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "checking iOS Simulator support"

if "$DOTFILES_ROOT/_scripts/mobile-setup" --check ios; then
  installer_success "iOS Simulator support ready"
else
  installer_warn "iOS Simulator support is incomplete"
  installer_hint "Run: mobile-setup ios"
fi
