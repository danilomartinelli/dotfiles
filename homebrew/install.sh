#!/usr/bin/env bash
#
# Ensure Homebrew is installed. Setup orchestration remains in _scripts/setup.

set -e

SCRIPT_PATH=${BASH_SOURCE[0]}
SCRIPT_DIR="$(CDPATH='' cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
HOMEBREW_AVAILABILITY=$SCRIPT_DIR/_availability.sh

download_and_install() {
  local installer_url
  local installer_file

  installer_url=$1
  installer_file=$(mktemp "${TMPDIR:-/tmp}/homebrew-installer.XXXXXX")

  echo '  Downloading Homebrew installer...'
  if ! curl -fsSL "$installer_url" -o "$installer_file"; then
    rm -f "$installer_file"
    echo '  ERROR: Failed to download Homebrew installer' >&2
    return 1
  fi

  if ! grep -q Homebrew "$installer_file"; then
    rm -f "$installer_file"
    echo "  ERROR: Downloaded script doesn't appear to be a Homebrew installer" >&2
    return 1
  fi

  echo '  Executing Homebrew installer...'
  if ! /bin/bash "$installer_file"; then
    rm -f "$installer_file"
    return 1
  fi

  rm -f "$installer_file"
}

if "$HOMEBREW_AVAILABILITY" prefix >/dev/null; then
  exit 0
fi

case "$(uname -s)" in
  Darwin|Linux)
    echo '  Installing Homebrew for you.'
    download_and_install 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
    ;;
  *)
    echo "  ERROR: Homebrew installation is unsupported on $(uname -s)" >&2
    exit 1
    ;;
esac

if ! "$HOMEBREW_AVAILABILITY" prefix >/dev/null; then
  echo '  ERROR: Homebrew installation completed, but brew was not found' >&2
  exit 1
fi

echo '  Homebrew installed successfully.'
