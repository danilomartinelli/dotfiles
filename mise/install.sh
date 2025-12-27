#!/bin/sh

set -e

# Validate mise is installed
if ! command -v mise >/dev/null 2>&1; then
  echo "Error: mise is not installed. Please install it first:" >&2
  echo "  brew install mise" >&2
  exit 1
fi

echo "› Installing Mise runtimes"
mise install

if [ $? -eq 0 ]; then
  echo "✓ Mise runtimes installed successfully"
else
  echo "Error: Failed to install Mise runtimes" >&2
  exit 1
fi
