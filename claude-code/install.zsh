#!/bin/sh

DOTFILES_CLAUDE_CODE="$HOME/.dotfiles/claude-code"
CLAUDE_CODE_CONFIG_FILE="$HOME/.config/claude-code/config.json"

# Create config directory if it doesn't exist
mkdir -p "$HOME/.config/claude-code"

# Remove existing files/links
[ -f "$CLAUDE_CODE_CONFIG_FILE" ] && rm "$CLAUDE_CODE_CONFIG_FILE"
[ -L "$CLAUDE_CODE_CONFIG_FILE" ] && rm "$CLAUDE_CODE_CONFIG_FILE"

# Create symlinks
ln -s "$DOTFILES_CLAUDE_CODE/config.json" "$CLAUDE_CODE_CONFIG_FILE"

echo "✓ claude-code symlinks created"
