#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting Archiver as default app for compressed files"

ARCHIVER_BUNDLE="com.incrediblebee.Archiver"
ARCHIVER_APP=${ARCHIVER_APP:-/Applications/Archiver.app}
PLIST_BUDDY_BIN=${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}
CODESIGN_BIN=${CODESIGN_BIN:-/usr/bin/codesign}
LSREGISTER_BIN=${LSREGISTER_BIN:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}

if ! "$PLIST_BUDDY_BIN" -c "Print :CFBundleIdentifier" "$ARCHIVER_APP/Contents/Info.plist" 2>/dev/null | grep -Fxq "$ARCHIVER_BUNDLE"; then
  installer_warn "Archiver app not found at $ARCHIVER_APP"
  installer_hint "Install Archiver from https://archiverapp.com/ and rerun dot."
  exit 0
fi

if ! "$CODESIGN_BIN" --verify --deep --strict "$ARCHIVER_APP" >/dev/null 2>&1; then
  installer_warn "Archiver has an invalid code signature; skipping file associations"
  installer_hint "Install a correctly signed Archiver build, then rerun dot."
  exit 0
fi

if [ ! -x "$LSREGISTER_BIN" ] || ! "$LSREGISTER_BIN" -f "$ARCHIVER_APP" >/dev/null 2>&1; then
  installer_warn "macOS could not register Archiver; skipping file associations"
  installer_hint "Open Archiver once, then rerun dot."
  exit 0
fi

installer_claim_file_types Archiver "$ARCHIVER_BUNDLE" \
  "Archiver set as default for compressed files"
