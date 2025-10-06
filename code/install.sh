#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up code configuration"

# Define paths
CODE_DIR="$HOME/Library/Application Support/Code/User"
DOTFILES_CODE="$HOME/.dotfiles/code"

# Create Code User directory if it doesn't exist
mkdir -p "$CODE_DIR"

# Remove existing files/links
[ -f "$CODE_DIR/settings.json" ] && rm "$CODE_DIR/settings.json"
[ -L "$CODE_DIR/settings.json" ] && rm "$CODE_DIR/settings.json"
[ -f "$CODE_DIR/keybindings.json" ] && rm "$CODE_DIR/keybindings.json"
[ -L "$CODE_DIR/keybindings.json" ] && rm "$CODE_DIR/keybindings.json"
[ -f "$CODE_DIR/mcp.json" ] && rm "$CODE_DIR/mcp.json"
[ -L "$CODE_DIR/mcp.json" ] && rm "$CODE_DIR/mcp.json"

# Create symlinks
ln -s "$DOTFILES_CODE/settings.json" "$CODE_DIR/settings.json"
ln -s "$DOTFILES_CODE/keybindings.json" "$CODE_DIR/keybindings.json"
ln -s "$DOTFILES_CODE/mcp.json" "$CODE_DIR/mcp.json"

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

curl "https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml" \
  | yq -r "to_entries | (map(.value.extensions) | flatten) - [null] | unique | .[]" \
  | grep -vE '\.html|\.htm' \
  | xargs -L 1 -I "{}" duti -s com.microsoft.VSCode {} all

echo "✓ code set as default editor for code files"

echo "› installing code extensions"

# Check if code command is available
if ! command -v code &> /dev/null; then
    echo "⚠️  code command not found in PATH"
    echo "Add Code to PATH: Open Code > Cmd+Shift+P > 'Install code command in PATH'"
    exit 1
fi

echo ""
echo "✅ Installation complete!"
