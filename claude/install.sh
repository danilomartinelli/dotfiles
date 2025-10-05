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

echo ""
echo "✅ Installation complete!"
echo "You can start Claude by running 'claude' in your terminal."
