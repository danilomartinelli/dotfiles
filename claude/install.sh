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
CLAUDE_AGENT_DIR="$HOME/.claude/agents"
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
DOTFILES_DIR="$HOME/.dotfiles/claude"

# Create Claude root directory if it doesn't exist
mkdir -p "$CLAUDE_ROOT_DIR"

# Create directories in dotfiles if they don't exist
mkdir -p "$DOTFILES_DIR/agents"
mkdir -p "$DOTFILES_DIR/commands"

# Remove existing files/links
[ -d "$CLAUDE_AGENT_DIR" ] && rm -rf "$CLAUDE_AGENT_DIR"
[ -L "$CLAUDE_AGENT_DIR" ] && rm "$CLAUDE_AGENT_DIR"
[ -d "$CLAUDE_COMMANDS_DIR" ] && rm -rf "$CLAUDE_COMMANDS_DIR"
[ -L "$CLAUDE_COMMANDS_DIR" ] && rm "$CLAUDE_COMMANDS_DIR"

# Create symlinks
ln -s "$DOTFILES_DIR/agents" "$CLAUDE_AGENT_DIR"
ln -s "$DOTFILES_DIR/commands" "$CLAUDE_COMMANDS_DIR"

echo "✓ claude symlinks created"

# Add MCP integrations
claude mcp add -s user playwright -- npx -y @playwright/mcp@latest

echo ""
echo "✅ Installation complete!"
echo "You can start Claude by running 'claude' in your terminal."
