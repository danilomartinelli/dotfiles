#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up VSCode configuration"

# Check if VSCode app exists
if [ ! -d "/Applications/Visual\ Studio\ Code.app" ]; then
  echo "Warning: VSCode app not found at /Applications/Visual\ Studio\ Code.app" >&2
  exit 0
fi

# Define paths
CODE_DIR="$HOME/Library/Application Support/Visual\ Studio\ Code/User"
DOTFILES_CODE="$HOME/.dotfiles/code"

# Validate source files exist
if [ ! -f "$DOTFILES_CODE/settings.json" ]; then
  echo "Error: Source file not found: $DOTFILES_CODE/settings.json" >&2
  exit 1
fi

if [ ! -f "$DOTFILES_CODE/keybindings.json" ]; then
  echo "Error: Source file not found: $DOTFILES_CODE/keybindings.json" >&2
  exit 1
fi

# Create VSCode User directory if it doesn't exist
mkdir -p "$CODE_DIR"

# Remove existing files/links
[ -f "$CODE_DIR/settings.json" ] && rm "$CODE_DIR/settings.json"
[ -L "$CODE_DIR/settings.json" ] && rm "$CODE_DIR/settings.json"
[ -f "$CODE_DIR/keybindings.json" ] && rm "$CODE_DIR/keybindings.json"
[ -L "$CODE_DIR/keybindings.json" ] && rm "$CODE_DIR/keybindings.json"

# Create symlinks
ln -s "$DOTFILES_CODE/settings.json" "$CODE_DIR/settings.json"
ln -s "$DOTFILES_CODE/keybindings.json" "$CODE_DIR/keybindings.json"

echo "✓ VSCode symlinks created"

# Set default editor for code files
echo "› setting VSCode as default editor for code files"

# Validate required tools are installed
if ! command -v python-yq >/dev/null 2>&1 && ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq or python-yq is required but not installed." >&2
  echo "  Install with: brew install python-yq" >&2
  exit 1
fi

# Use python-yq if available, fallback to yq
YQ_CMD=$(command -v python-yq 2>/dev/null || command -v yq 2>/dev/null)

if ! command -v duti >/dev/null 2>&1; then
  echo "Error: duti is required but not installed." >&2
  echo "  Install with: brew install duti" >&2
  exit 1
fi

# Validate curl is available
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required but not installed." >&2
  exit 1
fi

# com.microsoft.VSCode -> VSCode app bundle ID
echo "  Downloading language extensions list..."
if ! curl -fsSL "https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml" \
  | "$YQ_CMD" -r "to_entries | (map(.value.extensions) | flatten) - [null] | unique | .[]" 2>/dev/null \
  | grep -vE '\.html|\.htm' \
  | xargs -L 1 -I "{}" duti -s com.microsoft.VSCode {} all 2>/dev/null; then
  echo "Warning: Some file types could not be configured" >&2
  echo "  You may need to set VSCode as default editor manually" >&2
else
  echo "✓ VSCode set as default editor for code files"
fi

echo ""
echo "✅ Installation complete!"
