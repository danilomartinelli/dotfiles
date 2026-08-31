#!/bin/sh
# Apply the macOS preference catalog and named side-effect steps.

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
CATALOG=${DOTFILES_MACOS_DEFAULTS_CATALOG:-$SCRIPT_DIR/defaults.tsv}

# shellcheck source=_scripts/catalog.sh
. "$SCRIPT_DIR/../_scripts/catalog.sh"

# Printed in the installer vocabulary: setup runs these two under its own
# phase reporting, and the steps below are items inside that phase.
# shellcheck source=_scripts/installer-output.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_scripts/installer-output.sh"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: This script is only for macOS" >&2
  exit 1
fi

if [ ! -f "$CATALOG" ]; then
  echo "Error: defaults catalog not found: $CATALOG" >&2
  exit 1
fi

expand_value() {
  printf '%s\n' "$1" | sed "s|\$HOME|$HOME|g"
}

apply_catalog_row() {
  domain=$1
  key=$2
  type=$3
  value=$4

  if [ -z "$key" ] || [ -z "$type" ] || [ -z "$value" ]; then
    echo "Error: invalid catalog row: $domain $key    $type   $value" >&2
    exit 1
  fi

  value=$(expand_value "$value")

  case "$type" in
    bool)
      defaults write "$domain" "$key" -bool "$value"
      ;;
    int)
      defaults write "$domain" "$key" -int "$value"
      ;;
    float)
      defaults write "$domain" "$key" -float "$value"
      ;;
    string)
      defaults write "$domain" "$key" -string "$value"
      ;;
    *)
      echo "Error: unknown catalog type '$type' for $domain $key" >&2
      exit 1
      ;;
  esac
  return 0
}

# The screencapture location default is silently ignored by macOS unless the
# directory already exists, so create it before the catalog applies.
ensure_screenshot_dir() {
  mkdir -p "$HOME/Downloads/Screenshots"
}

show_library_folder() {
  if [ ! -d "$HOME/Library" ]; then
    return 0
  fi

  if chflags nohidden "$HOME/Library" 2>/dev/null; then
    xattr -d com.apple.FinderInfo "$HOME/Library" 2>/dev/null || true
    installer_item "Library folder is now visible"
  else
    installer_warn "Failed to show Library folder"
  fi
}

# Advisory: point the default browser at Dia. macOS shows a one-click
# confirmation dialog the first time; the script does not wait for it.
set_default_browser() {
  if ! command -v defaultbrowser >/dev/null 2>&1; then
    installer_hint "defaultbrowser not installed yet; skipping default browser"
    return 0
  fi
  if defaultbrowser 2>/dev/null | grep -q '^\* *dia$'; then
    installer_item "Dia already the default browser"
  elif defaultbrowser dia 2>/dev/null; then
    installer_item "Default browser set to Dia (confirm the macOS dialog)"
  else
    installer_warn "could not set the default browser (is Dia installed?)"
  fi
}

restart_services() {
  installer_note "Restarting system services..."
  # cfprefsd is deliberately absent: killing it right after `defaults write`
  # can discard preferences still buffered in the daemon.
  killall Finder Dock SystemUIServer ControlCenter ControlStrip 2>/dev/null || true
  installer_item "Services restarted (log out to apply keyboard settings)"
}

ensure_screenshot_dir
catalog_each_row "$CATALOG" apply_catalog_row
show_library_folder
set_default_browser
restart_services
