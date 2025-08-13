#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting Ghostty as default terminal app for shell files"

GHOSTTY_BUNDLE="com.mitchellh.ghostty"
EXTENSIONS=".sh .command .terminal"

for ext in $EXTENSIONS; do
  duti -s $GHOSTTY_BUNDLE $ext all
done

echo "✓ Ghostty set as default for terminal-related files"

DOTFILES_GHOSTTY="$HOME/.dotfiles/ghostty"
GHOSTTY_CONFIG_DIR="$HOME/.ghostty-config"

# Create Ghostty config directory if it doesn't exist
mkdir -p "$GHOSTTY_CONFIG_DIR"

# Remove existing files/links
[ -f "$GHOSTTY_CONFIG_DIR/config" ] && rm "$GHOSTTY_CONFIG_DIR/config"
[ -L "$GHOSTTY_CONFIG_DIR/config" ] && rm "$GHOSTTY_CONFIG_DIR/config"

# Create symlinks
ln -s "$DOTFILES_GHOSTTY/config" "$GHOSTTY_CONFIG_DIR/config"

echo "✓ ghostty symlinks created"
