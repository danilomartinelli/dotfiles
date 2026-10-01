#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Conductor configuration"

# The Settings window writes this file, so a change made there lands here as a
# diff to keep or discard. Repository settings live in each repository's own
# .conductor/settings.toml.
mkdir -p "$HOME/.conductor"
installer_link_config --label "Conductor settings" \
  "$TOPIC_DIR/settings.toml" "$HOME/.conductor/settings.toml"

installer_success "Conductor configured"
