#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

# Check if Claude command is available
if ! command -v claude &> /dev/null; then
    echo "⚠️  claude command not found in PATH"
    echo "Adding Claude to PATH..."
    curl -fsSL https://claude.ai/install.sh | bash -s latest
fi

echo "› setting up claude configuration..."

# Define paths
CLAUDE_ROOT_DIR="$HOME/.claude"
CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
DOTFILES_DIR="$HOME/.dotfiles/claude"

# Create Claude root directory if it doesn't exist
mkdir -p "$CLAUDE_ROOT_DIR"

# Remove existing files/links
[ -f "$CLAUDE_SETTINGS_FILE" ] && rm "$CLAUDE_SETTINGS_FILE"
[ -L "$CLAUDE_SETTINGS_FILE" ] && rm "$CLAUDE_SETTINGS_FILE"

# Create symlinks
ln -s "$DOTFILES_DIR/settings.json" "$CLAUDE_SETTINGS_FILE"

echo "✓ claude symlinks created"

echo ""
echo "✅ Installation complete!"
echo "You can start Claude by running 'claude' in your terminal."
