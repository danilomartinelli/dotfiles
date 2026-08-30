#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting Skim as default PDF viewer"

installer_optional_app Skim skim /Applications/Skim.app

installer_skip_if_applied skim-associations "file associations" "Skim configured"

installer_optional_command duti \
  "duti is required to set Skim as the default PDF viewer"

SKIM_BUNDLE="net.sourceforge.skim-app.skim"

installer_apply_associations Skim "$SKIM_BUNDLE" \
  "Skim set as default app for PDF files"

installer_mark_applied skim-associations

installer_success "Skim configured"
