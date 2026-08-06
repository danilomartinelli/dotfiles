#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring Raycast script commands"

installer_require_app Raycast raycast "/Applications/Raycast.app"

SCRIPTS_DIR="$TOPIC_DIR/scripts"

# Raycast stores most settings in its own sync store; script commands are the
# durable, repo-friendly surface. Point Raycast at this directory once:
#   Raycast → Settings → Extensions → Script Commands → Add Directories
installer_success "Script commands live in $SCRIPTS_DIR"
installer_note "Add that folder in Raycast → Settings → Extensions → Script Commands"

# Sensible first-run defaults when the preference domain exists.
defaults write com.raycast.macos SUEnableAutomaticChecks -bool true 2>/dev/null || true

installer_success "Raycast configured"
