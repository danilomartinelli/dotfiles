#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Bartender"

installer_require_app Bartender bartender \
  "/Applications/Bartender 6.app" "/Applications/Bartender.app"

# No `defaults write` here: modern Bartender manages launch-at-login via
# SMAppService and persists its own preferences on quit, so scripted writes
# are silently overwritten. Everything is configured in the app UI.

installer_note 'Open Bartender manually when you are ready to grant permissions'
installer_success 'Bartender configured (hide/show items are configured in the app UI)'
