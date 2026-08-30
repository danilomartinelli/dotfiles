#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting Skim as default PDF viewer"

installer_optional_app Skim skim /Applications/Skim.app

SKIM_BUNDLE="net.sourceforge.skim-app.skim"

installer_claim_file_types Skim "$SKIM_BUNDLE" \
  "Skim set as default app for PDF files"
