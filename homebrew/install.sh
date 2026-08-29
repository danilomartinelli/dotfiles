#!/usr/bin/env bash
#
# Ensure Homebrew is installed. Setup orchestration remains in _scripts/setup.

set -e

INSTALLER_ANCHOR=${BASH_SOURCE[0]}
# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$INSTALLER_ANCHOR")/../_scripts" && pwd)/installer-preamble.sh"

HOMEBREW_AVAILABILITY=$TOPIC_DIR/_availability.sh

download_and_install() {
  local installer_url
  local installer_file

  installer_url=$1
  installer_file=$(mktemp "${TMPDIR:-/tmp}/homebrew-installer.XXXXXX")

  installer_note 'downloading Homebrew installer...'
  if ! curl -fsSL "$installer_url" -o "$installer_file"; then
    rm -f "$installer_file"
    installer_error 'Failed to download Homebrew installer'
    return 1
  fi

  if ! grep -q Homebrew "$installer_file"; then
    rm -f "$installer_file"
    installer_error "Downloaded script doesn't appear to be a Homebrew installer"
    return 1
  fi

  installer_note 'executing Homebrew installer...'
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
  Darwin | Linux)
    installer_note 'installing Homebrew for you'
    download_and_install 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
    ;;
  *)
    installer_fail "Homebrew installation is unsupported on $(uname -s)"
    ;;
esac

if ! "$HOMEBREW_AVAILABILITY" prefix >/dev/null; then
  installer_fail 'Homebrew installation completed, but brew was not found'
fi

installer_success 'Homebrew installed successfully.'
