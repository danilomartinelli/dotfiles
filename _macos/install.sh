#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring macOS defaults"

# Get the directory of this script
MACOS_DIR="$(dirname "$0")"

# Validate script directory exists
if [ ! -d "$MACOS_DIR" ]; then
  echo "Error: macOS directory not found: $MACOS_DIR" >&2
  exit 1
fi

# Run the defaults script
if [ -f "$MACOS_DIR/set-defaults.sh" ]; then
  if ! sh "$MACOS_DIR/set-defaults.sh"; then
    echo "Warning: set-defaults.sh encountered errors" >&2
    exit 1
  fi
else
  echo "Warning: set-defaults.sh not found" >&2
fi

# Run the hostname script
if [ -f "$MACOS_DIR/set-hostname.sh" ]; then
  if ! sh "$MACOS_DIR/set-hostname.sh"; then
    echo "Warning: set-hostname.sh encountered errors" >&2
    # Don't exit on hostname script failure, it's not critical
  fi
else
  echo "Warning: set-hostname.sh not found" >&2
fi

echo "✓ macOS configuration complete"
