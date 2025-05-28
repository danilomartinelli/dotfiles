#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up vscode configuration"

# Define paths
VSCODE_DIR="$HOME/Library/Application Support/Code/User"
DOTFILES_VSCODE=$(pwd -P)

# Create VS Code User directory if it doesn't exist
mkdir -p "$VSCODE_DIR"

# Remove existing files/links
[ -L "$VSCODE_DIR/settings.json" ] && rm "$VSCODE_DIR/settings.json"

# Create symlinks
ln -s "$DOTFILES_VSCODE/settings.jsonc" "$VSCODE_DIR/settings.json"

echo "✓ vscode symlinks created"
