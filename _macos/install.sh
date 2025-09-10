#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring macOS defaults"

# Get the directory of this script
MACOS_DIR="$(dirname "$0")"

# Run the defaults script
if [ -f "$MACOS_DIR/set-defaults.sh" ]; then
  sh "$MACOS_DIR/set-defaults.sh"
fi

# Run the hostname script
if [ -f "$MACOS_DIR/set-hostname.sh" ]; then
  sh "$MACOS_DIR/set-hostname.sh"
fi

echo "✓ macOS configuration complete"