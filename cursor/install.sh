#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up cursor configuration"

# Define paths
CURSOR_DIR="$HOME/Library/Application Support/Cursor/User"
DOTFILES_CURSOR="$HOME/.dotfiles/cursor"

# Create Cursor User directory if it doesn't exist
mkdir -p "$CURSOR_DIR"

# Remove existing files/links
[ -f "$CURSOR_DIR/settings.json" ] && rm "$CURSOR_DIR/settings.json"
[ -L "$CURSOR_DIR/settings.json" ] && rm "$CURSOR_DIR/settings.json"

# Create symlinks
ln -s "$DOTFILES_CURSOR/settings.json" "$CURSOR_DIR/settings.json"

echo "✓ cursor symlinks created"

# Set default editor for code files
echo "› setting cursor as default editor for code files"

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
  | xargs -L 1 -I "{}" duti -s com.todesktop.230313mzl4w4u92 {} all

echo "✓ cursor set as default editor for code files"

# Extensões Core - Ordem Alfabética
extensions=(
  "aaron-bond.better-comments"
  "anthropic.claude-code"
  "antfu.file-nesting"
  "bierner.markdown-preview-github-styles"
  "bradlc.vscode-tailwindcss"
  "christian-kohler.path-intellisense"
  "dbaeumer.vscode-eslint"
  "eamodio.gitlens"
  "esbenp.prettier-vscode"
  "formulahendry.auto-rename-tag"
  "graphql.vscode-graphql"
  "graphql.vscode-graphql-syntax"
  "hashicorp.terraform"
  "jock.svg"
  "mikestead.dotenv"
  "monokai.theme-monokai-pro-vscode"
  "mrmlnc.vscode-duplicate"
  "ms-azuretools.vscode-docker"
  "ms-vscode.vscode-typescript-next"
  "naumovs.color-highlight"
  "pflannery.vscode-versionlens"
  "prisma.prisma"
  "rangav.vscode-thunder-client"
  "redhat.vscode-yaml"
  "streetsidesoftware.code-spell-checker"
  "streetsidesoftware.code-spell-checker-portuguese-brazilian"
  "styled-components.vscode-styled-components"
  "tamasfe.even-better-toml"
  "unifiedjs.vscode-mdx"
  "usernamehw.errorlens"
  "waderyan.gitblame"
  "wix.vscode-import-cost"
  "yoavbls.pretty-ts-errors"
)

echo "› installing cursor extensions"

# Check if cursor command is available
if ! command -v cursor &> /dev/null; then
    echo "⚠️  cursor command not found in PATH"
    echo "Add Cursor to PATH: Open Cursor > Cmd+Shift+P > 'Install cursor command in PATH'"
    exit 1
fi

# Install all extensions
installed=0
failed=0

for ext in "${extensions[@]}"; do
  echo "Installing: $ext"
  if cursor --install-extension "$ext" --force 2>/dev/null; then
    ((installed++))
  else
    echo "  ⚠️  Failed to install: $ext"
    ((failed++))
  fi
done

echo ""
echo "✅ Installation complete!"
echo "   Installed: $installed extensions"
[ $failed -gt 0 ] && echo "   Failed: $failed extensions"

# Restart Cursor if it's running
if pgrep -x "Cursor" > /dev/null; then
    echo ""
    echo "› Cursor is running. Please restart it to apply all changes."
    echo "  Press Cmd+Q and reopen Cursor."
fi
