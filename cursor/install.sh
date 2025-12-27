#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up Cursor configuration"

# Check if Cursor app exists
if [ ! -d "/Applications/Cursor.app" ]; then
  echo "Warning: Cursor app not found at /Applications/Cursor.app" >&2
  echo "  Install Cursor from: https://cursor.sh/" >&2
  exit 0
fi

# Define paths
CURSOR_DIR="$HOME/Library/Application Support/Cursor/User"
DOTFILES_CURSOR="$HOME/.dotfiles/cursor"

# Validate source files exist
if [ ! -f "$DOTFILES_CURSOR/settings.json" ]; then
  echo "Error: Source file not found: $DOTFILES_CURSOR/settings.json" >&2
  exit 1
fi

if [ ! -f "$DOTFILES_CURSOR/keybindings.json" ]; then
  echo "Error: Source file not found: $DOTFILES_CURSOR/keybindings.json" >&2
  exit 1
fi

# Create Cursor User directory if it doesn't exist
mkdir -p "$CURSOR_DIR"

# Remove existing files/links
[ -f "$CURSOR_DIR/settings.json" ] && rm "$CURSOR_DIR/settings.json"
[ -L "$CURSOR_DIR/settings.json" ] && rm "$CURSOR_DIR/settings.json"
[ -f "$CURSOR_DIR/keybindings.json" ] && rm "$CURSOR_DIR/keybindings.json"
[ -L "$CURSOR_DIR/keybindings.json" ] && rm "$CURSOR_DIR/keybindings.json"

# Create symlinks
ln -s "$DOTFILES_CURSOR/settings.json" "$CURSOR_DIR/settings.json"
ln -s "$DOTFILES_CURSOR/keybindings.json" "$CURSOR_DIR/keybindings.json"

echo "✓ Cursor symlinks created"

# Set default editor for code files
echo "› setting Cursor as default editor for code files"

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

# com.todesktop.230313mzl4w4u92 -> Cursor app bundle ID
echo "  Downloading language extensions list..."
if ! curl -fsSL "https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml" \
  | "$YQ_CMD" -r "to_entries | (map(.value.extensions) | flatten) - [null] | unique | .[]" 2>/dev/null \
  | grep -vE '\.html|\.htm' \
  | xargs -L 1 -I "{}" duti -s com.todesktop.230313mzl4w4u92 {} all 2>/dev/null; then
  echo "Warning: Some file types could not be configured" >&2
  echo "  You may need to set Cursor as default editor manually" >&2
else
  echo "✓ Cursor set as default editor for code files"
fi

echo ""
echo "✅ Installation complete!"
