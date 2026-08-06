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
    echo "  ✓ Library folder is now visible"
  else
    echo "  Warning: Failed to show Library folder" >&2
  fi
}

restart_services() {
  echo "  → Restarting system services..."
  # cfprefsd is deliberately absent: killing it right after `defaults write`
  # can discard preferences still buffered in the daemon.
  killall Finder Dock SystemUIServer ControlCenter ControlStrip 2>/dev/null || true
  echo "  ✓ Services restarted (log out to apply keyboard settings)"
}

ensure_screenshot_dir
apply_catalog
show_library_folder
restart_services
