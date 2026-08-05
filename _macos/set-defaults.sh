#!/bin/sh
# Apply the macOS preference catalog and named side-effect steps.

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
CATALOG=${DOTFILES_MACOS_DEFAULTS_CATALOG:-$SCRIPT_DIR/defaults.tsv}

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

apply_catalog() {
  while IFS="$(printf '\t')" read -r domain key type value || [ -n "${domain:-}" ]; do
    case "${domain:-}" in
      '' | \#*)
        domain=
        continue
        ;;
    esac

    if [ -z "${key:-}" ] || [ -z "${type:-}" ] || [ -z "${value:-}" ]; then
      echo "Error: invalid catalog row: $domain	$key	$type	$value" >&2
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
    domain=
  done <"$CATALOG"
}

configure_dns() {
  if ! command -v networksetup >/dev/null 2>&1; then
    echo "  Warning: networksetup not found, skipping DNS configuration" >&2
    return 0
  fi

  if sudo -n true 2>/dev/null || sudo -v; then
    if sudo networksetup -setdnsservers Wi-Fi 8.8.8.8 8.8.4.4 2>/dev/null; then
      echo "  ✓ DNS servers configured"
    else
      echo "  Warning: Failed to set DNS servers (may require admin privileges)" >&2
    fi
  else
    echo "  Warning: Skipping DNS configuration (sudo access required)" >&2
  fi
}

show_library_folder() {
  if [ ! -d "$HOME/Library" ]; then
    return 0
  fi

  if chflags nohidden "$HOME/Library" 2>/dev/null; then
    xattr -d com.apple.FinderInfo "$HOME/Library" 2>/dev/null || true
    echo "  ✓ Library folder is now visible"
  else
    echo "  Warning: Failed to show Library folder" >&2
  fi
}

restart_services() {
  echo "  → Restarting system services..."
  killall Finder Dock SystemUIServer ControlCenter ControlStrip cfprefsd 2>/dev/null || true
  echo "  ✓ Services restarted (log out to apply keyboard settings)"
}

apply_catalog
configure_dns
show_library_folder
restart_services
