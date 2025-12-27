#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up Warp configuration"

# Define paths
WARP_DIR="$HOME/.warp"
DOTFILES_WARP_DIR="$HOME/.dotfiles/warp"

# Create Warp directory if it doesn't exist
mkdir -p "$WARP_DIR"

# Set Warp as default terminal handler
defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{LSHandlerContentType=public.unix-executable;LSHandlerRoleAll=com.warpdotdev.warp-stable;}'

echo "✓ Warp configured as default terminal"

# Note: Warp settings are cloud-synced, so no local symlinks needed
# Launch configurations and themes are managed within Warp UI

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Open Warp and sign in to sync your settings"
echo "  2. Create a Launch Configuration for ~/Code workspace"
echo "  3. Press CMD+, to customize preferences"
