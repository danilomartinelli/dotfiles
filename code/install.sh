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

# Create symlinks
ln -s "$DOTFILES_CODE/settings.json" "$CODE_DIR/settings.json"
ln -s "$DOTFILES_CODE/keybindings.json" "$CODE_DIR/keybindings.json"

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

# Core Extensions - Alphabetical Order
extensions=(
  "1yib.rust-bundle"
  "amazonwebservices.aws-toolkit-vscode"
  "antfu.file-nesting"
  "anthropic.claude-code"
  "bierner.markdown-checkbox"
  "bierner.markdown-emoji"
  "bierner.markdown-footnotes"
  "bierner.markdown-mermaid"
  "bierner.markdown-preview-github-styles"
  "bierner.markdown-yaml-preamble"
  "bradlc.vscode-tailwindcss"
  "chakrounanas.turbo-console-log"
  "christian-kohler.npm-intellisense"
  "christian-kohler.path-intellisense"
  "codezombiech.gitignore"
  "csstools.postcss"
  "davidanson.vscode-markdownlint"
  "dbaeumer.vscode-eslint"
  "docker.docker"
  "dustypomerleau.rust-syntax"
  "eamodio.gitlens"
  "esbenp.prettier-vscode"
  "fill-labs.dependi"
  "firsttris.vscode-jest-runner"
  "formulahendry.auto-close-tag"
  "formulahendry.auto-rename-tag"
  "github.copilot"
  "github.copilot-chat"
  "golang.go"
  "gruntfuggly.todo-tree"
  "hashicorp.terraform"
  "humao.rest-client"
  "jock.svg"
  "miguelsolorio.fluent-icons"
  "mikestead.dotenv"
  "monokai.theme-monokai-pro-vscode"
  "ms-azuretools.vscode-containers"
  "ms-kubernetes-tools.vscode-kubernetes-tools"
  "ms-playwright.playwright"
  "ms-python.debugpy"
  "ms-python.python"
  "ms-python.vscode-pylance"
  "ms-python.vscode-python-envs"
  "ms-vscode-remote.remote-containers"
  "ms-vscode-remote.remote-ssh"
  "ms-vscode-remote.remote-ssh-edit"
  "ms-vscode.live-server"
  "ms-vscode.remote-explorer"
  "ms-vscode.vscode-typescript-next"
  "naumovs.color-highlight"
  "nrwl.angular-console"
  "orta.vscode-jest"
  "pflannery.vscode-versionlens"
  "redhat.vscode-yaml"
  "ritwickdey.liveserver"
  "robole.file-bunny"
  "rust-lang.rust-analyzer"
  "stivo.tailwind-fold"
  "tamasfe.even-better-toml"
  "tyriar.sort-lines"
  "usernamehw.errorlens"
  "waderyan.gitblame"
  "wix.vscode-import-cost"
  "yoavbls.pretty-ts-errors"
)

echo "› installing code extensions"

# Check if code command is available
if ! command -v code &> /dev/null; then
    echo "⚠️  code command not found in PATH"
    echo "Add Code to PATH: Open Code > Cmd+Shift+P > 'Install code command in PATH'"
    exit 1
fi

# Install all extensions
installed=0
failed=0

for ext in "${extensions[@]}"; do
  echo "Installing: $ext"
  if code --install-extension "$ext" --force 2>/dev/null; then
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

# Restart Code if it's running
if pgrep -x "Code" > /dev/null; then
    echo ""
    echo "› Code is running. Please restart it to apply all changes."
    echo "  Press Cmd+Q and reopen Code."
fi
