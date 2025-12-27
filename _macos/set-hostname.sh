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

# Validate scutil exists
if ! command -v scutil >/dev/null 2>&1; then
  echo "Error: scutil is required but not available." >&2
  exit 1
fi

# Get current hostname
if ! hostname=$(scutil --get LocalHostName 2>/dev/null); then
  echo "Warning: Failed to get current hostname" >&2
  exit 0
fi

# If hostname is empty, skip
if [ -z "$hostname" ]; then
  echo "Info: No hostname set, skipping" >&2
  exit 0
fi

# If hostname contains a hyphen and then a number, remove the hyphen and number
normal_hostname=$(echo "$hostname" | sed 's/-[0-9]*$//')

# If our hostname was changed by macOS, change it back
if [ "$normal_hostname" != "$hostname" ]; then
  echo "  → Changing hostname from $hostname to $normal_hostname"
  if scutil --set LocalHostName "$normal_hostname" 2>/dev/null; then
    if scutil --set ComputerName "$normal_hostname" 2>/dev/null; then
      echo "  ✓ Hostname updated successfully"
    else
      echo "  Warning: Failed to set ComputerName" >&2
    fi
  else
    echo "  Warning: Failed to set LocalHostName (may require admin privileges)" >&2
    exit 0
  fi
else
  echo "  ✓ Hostname is already normalized: $hostname"
fi
