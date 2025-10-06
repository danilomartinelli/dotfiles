#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up iTerm2 configuration"

# Define paths
ITERM2_DIR="$HOME/Library/Application Support/iTerm2"
ITERM2_PROFILES_DIR="$ITERM2_DIR/DynamicProfiles"
DOTFILES_ITERM2_DIR="$HOME/.dotfiles/iterm2"

# Create iTerm2 Profiles directory if it doesn't exist
mkdir -p "$ITERM2_PROFILES_DIR"

# Remove existing files/links
[ -f "$ITERM2_PROFILES_DIR/profile.json" ] && rm "$ITERM2_PROFILES_DIR/profile.json"
[ -L "$ITERM2_PROFILES_DIR/profile.json" ] && rm "$ITERM2_PROFILES_DIR/profile.json"

# Create symlinks
ln -s "$DOTFILES_ITERM2_DIR/profile.json" "$ITERM2_PROFILES_DIR/profile.json"

echo "✓ iTerm2 symlinks created"

echo ""
echo "✅ Installation complete!"
