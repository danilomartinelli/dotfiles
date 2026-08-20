#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting Skim as default PDF viewer"

installer_require_app Skim skim /Applications/Skim.app

installer_require_command duti

SKIM_BUNDLE="net.sourceforge.skim-app.skim"

# Role "editor" is used throughout — never "all" — so that the viewer role
# registered by macOS Preview is not claimed unexpectedly.
EXTENSIONS=".pdf"

failed=0
for ext in $EXTENSIONS; do
  if ! duti -s "$SKIM_BUNDLE" "$ext" editor 2>/dev/null; then
    failed=$((failed + 1))
  fi
done

# Broad UTI for PDF documents when Launch Services supports it.
duti -s "$SKIM_BUNDLE" com.adobe.pdf editor 2>/dev/null || true

if [ "$failed" -eq 0 ]; then
  installer_success "Skim set as default app for PDF files"
else
  installer_warn "Some Skim file associations could not be configured ($failed failed)"
fi

installer_success "Skim configured"
