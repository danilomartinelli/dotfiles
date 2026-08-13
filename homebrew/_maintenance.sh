#!/bin/sh
#
# Remove known legacy Homebrew state that is no longer declared by this repo.

set -eu

SCRIPT_PATH=$0
SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
HOMEBREW_AVAILABILITY=$SCRIPT_DIR/_availability.sh
BREW_BIN=

# These taps used to be declared by this repository. Remove one only when no
# installed formula or cask still belongs to it.
LEGACY_TAPS='xo/xo'

usage() {
  cat >&2 <<'EOF'
Usage: homebrew/_maintenance.sh [--brew <path>]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --brew)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      BREW_BIN=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ -z "$BREW_BIN" ]; then
  BREW_BIN=$("$HOMEBREW_AVAILABILITY" binary) || {
    echo "homebrew/_maintenance.sh: brew executable not available" >&2
    exit 1
  }
fi

tap_has_installed_items() {
  maintenance_tap=$1
  maintenance_formulae=$("$BREW_BIN" list --formula --full-name) || return 2
  maintenance_casks=$("$BREW_BIN" list --cask --full-name) || return 2
  maintenance_items=$(printf '%s\n%s\n' "$maintenance_formulae" "$maintenance_casks")

  while IFS= read -r maintenance_item; do
    case "$maintenance_item" in
      "$maintenance_tap"/*) return 0 ;;
    esac
  done <<EOF
$maintenance_items
EOF

  return 1
}

tap_is_installed() {
  maintenance_expected_tap=$1
  maintenance_taps=$("$BREW_BIN" tap) || return 2

  while IFS= read -r maintenance_current_tap; do
    [ "$maintenance_current_tap" = "$maintenance_expected_tap" ] && return 0
  done <<EOF
$maintenance_taps
EOF

  return 1
}

for tap in $LEGACY_TAPS; do
  if tap_is_installed "$tap"; then
    :
  else
    maintenance_status=$?
    if [ "$maintenance_status" -eq 2 ]; then
      echo "Warning: could not inspect Homebrew taps; preserving legacy tap $tap" >&2
    fi
    continue
  fi

  if tap_has_installed_items "$tap"; then
    echo "Warning: preserving legacy tap $tap because it still owns installed packages" >&2
    continue
  else
    maintenance_status=$?
  fi

  if [ "$maintenance_status" -eq 2 ]; then
    echo "Warning: could not inspect installed packages; preserving legacy tap $tap" >&2
    continue
  fi

  "$BREW_BIN" untap "$tap"
  printf 'Removed unused legacy Homebrew tap: %s\n' "$tap"
done
