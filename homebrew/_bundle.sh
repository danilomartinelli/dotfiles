#!/bin/sh
#
# Reconcile declared Homebrew taps/trust and the Brewfile.

set -eu

SCRIPT_PATH=$0
SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
HOMEBREW_AVAILABILITY=$SCRIPT_DIR/_availability.sh
DOTFILES_ROOT=${DOTFILES_ROOT:-$(CDPATH='' cd -P -- "$SCRIPT_DIR/.." && pwd)}
BREW_BIN=
BREWFILE=$DOTFILES_ROOT/Brewfile

# Third-party taps that Homebrew must explicitly trust (not expressible in Brewfile).
TRUSTED_TAPS='nikitabobko/tap psviderski/tap vultr/vultr-cli'

usage() {
  cat >&2 <<'EOF'
Usage: homebrew/_bundle.sh [--brew <path>] [--file <Brewfile>]
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
    --file)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      BREWFILE=$2
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
    echo "homebrew/_bundle.sh: brew executable not available" >&2
    exit 1
  }
fi

if [ ! -f "$BREWFILE" ]; then
  echo "homebrew/_bundle.sh: Brewfile not found: $BREWFILE" >&2
  exit 1
fi

# Trustable third-party taps must exist before brew bundle installs their formulae or casks.
for tap in $TRUSTED_TAPS; do
  "$BREW_BIN" tap "$tap" || exit 1
  if ! "$BREW_BIN" trust --tap "$tap"; then
    echo "Warning: Homebrew trust $tap failed; continuing" >&2
  fi
done

"$BREW_BIN" bundle --file "$BREWFILE"
