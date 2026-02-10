#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up WezTerm configuration"

# Define paths
WEZTERM_DIR="$HOME/.wezterm"
DOTFILES_WEZTERM_DIR="$HOME/.dotfiles/wezterm"

# Create WezTerm directory if it doesn't exist
mkdir -p "$WEZTERM_DIR"

# Set WezTerm as default terminal handler
if ! defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{LSHandlerContentType=public.unix-executable;LSHandlerRoleAll=com.github.wez.wezterm;}' 2>/dev/null; then
  echo "Warning: Failed to set WezTerm as default terminal handler" >&2
  echo "  You may need to set it manually in System Settings" >&2
fi

echo "✓ WezTerm configured as default terminal"
