#!/bin/sh
#
# This corrects a point of confusion with macOS where if you bounce
# between wireless and wired connections, macOS will suddenly throw up its hands
# and add a random number to your hostname. Do it a couple times and you're
# in like, the thousands appended to your hostname, which makes you look like a
# chump when your machine is called "incredible-programmer-9390028", like
# you're behind 9,390,027 other better programmers before you. Sheesh.
#
# Anyway, this runs in `dot` and only asks for your permission (usually TouchID)
# if it actually needs to change your hostname for you, otherwise it's fast to
# toss into `dot` anyway.
#
# None of this really matters in the big scheme of things, but it bothered me.

set -e

# Printed in the installer vocabulary: setup runs this under its own phase
# reporting, and the steps below are items inside that phase.
SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
# shellcheck source=_scripts/installer-output.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_scripts/installer-output.sh"

# Validate scutil exists
if ! command -v scutil >/dev/null 2>&1; then
  installer_error "scutil is required but not available."
  exit 1
fi

# Get current hostname
if ! hostname=$(scutil --get LocalHostName 2>/dev/null); then
  installer_warn "Failed to get current hostname"
  exit 1
fi

# If hostname is empty, skip
if [ -z "$hostname" ]; then
  installer_note "No hostname set, skipping"
  exit 0
fi

# If hostname contains a hyphen and then a number, remove the hyphen and number
normal_hostname=$(echo "$hostname" | sed 's/-[0-9]*$//')

# If our hostname was changed by macOS, change it back
if [ "$normal_hostname" != "$hostname" ]; then
  installer_note "Changing hostname from $hostname to $normal_hostname"
  if scutil --set LocalHostName "$normal_hostname" 2>/dev/null; then
    if scutil --set ComputerName "$normal_hostname" 2>/dev/null; then
      installer_item "Hostname updated successfully"
    else
      installer_warn "Failed to set ComputerName"
      exit 1
    fi
  else
    installer_warn "Failed to set LocalHostName (may require admin privileges)"
    exit 1
  fi
else
  installer_item "Hostname is already normalized: $hostname"
fi
