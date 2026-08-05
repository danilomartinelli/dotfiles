#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Hermes Agent"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
mkdir -p "$HERMES_HOME"

if command -v hermes >/dev/null 2>&1; then
  installer_success "hermes CLI available"
else
  installer_note "Install Hermes with: brew install hermes-agent"
fi

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Configure provider/model with: hermes model"
installer_note "Or run the full wizard with: hermes setup"
installer_success "Hermes Agent configured"
