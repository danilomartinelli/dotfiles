#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up code configuration"

# Define paths
CURSOR_DIR="$HOME/Library/Application Support/Cursor/User"
DOTFILES_CURSOR="$HOME/.dotfiles/cursor"

# Create Code User directory if it doesn't exist
mkdir -p "$CURSOR_DIR"

# Remove existing files/links
[ -f "$CURSOR_DIR/settings.json" ] && rm "$CURSOR_DIR/settings.json"
[ -L "$CURSOR_DIR/settings.json" ] && rm "$CURSOR_DIR/settings.json"
[ -f "$CURSOR_DIR/keybindings.json" ] && rm "$CURSOR_DIR/keybindings.json"
[ -L "$CURSOR_DIR/keybindings.json" ] && rm "$CURSOR_DIR/keybindings.json"

# Create symlinks
ln -s "$DOTFILES_CURSOR/settings.json" "$CURSOR_DIR/settings.json"
ln -s "$DOTFILES_CURSOR/keybindings.json" "$CURSOR_DIR/keybindings.json"

echo "✓ code symlinks created"

# Set default editor for code files
echo "› setting code as default editor for code files"

# Check if required tools are installed
if ! command -v yq &> /dev/null; then
    echo "⚠️  yq not found, installing..."
    brew install yq
fi

if ! command -v duti &> /dev/null; then
    echo "⚠️  duti not found, installing..."
    brew install duti
fi

# com.todesktop.230313mzl4w4u92 -> Cursor app bundle ID
curl "https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml" \
  | yq -r "to_entries | (map(.value.extensions) | flatten) - [null] | unique | .[]" \
  | grep -vE '\.html|\.htm' \
  | xargs -L 1 -I "{}" duti -s com.todesktop.230313mzl4w4u92 {} all

echo "✓ cursor set as default editor for code files"

echo ""
echo "✅ Installation complete!"
