#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up windsurf configuration"

# Define paths
WINDSURF_DIR="$HOME/Library/Application Support/Windsurf/User"
DOTFILES_WINDSURF="$HOME/.dotfiles/windsurf"

# Create VS Code User directory if it doesn't exist
mkdir -p "$WINDSURF_DIR"

# Remove existing files/links
[ -f "$WINDSURF_DIR/settings.json" ] && rm "$WINDSURF_DIR/settings.json"
[ -L "$WINDSURF_DIR/settings.json" ] && rm "$WINDSURF_DIR/settings.json"

# Create symlinks
ln -s "$DOTFILES_WINDSURF/settings.json" "$WINDSURF_DIR/settings.json"

echo "✓ windsurf symlinks created"

# Set default editor for code files
echo "› setting windsurf as default editor for code files"

curl "https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml" \
  | yq -r "to_entries | (map(.value.extensions) | flatten) - [null] | unique | .[]" \
  | grep -vE '\.html|\.htm' \
  | xargs -L 1 -I "{}" duti -s com.exafunction.windsurf {} all

echo "✓ windsurf set as default editor for code files"

surf --install-extension aaron-bond.better-comments --force
surf --install-extension bradlc.vscode-tailwindcss --force
surf --install-extension christian-kohler.path-intellisense --force
surf --install-extension csstools.postcss --force
surf --install-extension dbaeumer.vscode-eslint --force
surf --install-extension eamodio.gitlens --force
surf --install-extension esbenp.prettier-vscode --force
surf --install-extension figma.figma-vscode-extension --force
surf --install-extension formulahendry.auto-close-tag --force
surf --install-extension formulahendry.auto-rename-tag --force
surf --install-extension jock.svg --force
surf --install-extension mechatroner.rainbow-csv --force
surf --install-extension mikestead.dotenv --force
surf --install-extension monokai.theme-monokai-pro-vscode --force
surf --install-extension ms-vscode.vscode-typescript-next --force
surf --install-extension redhat.vscode-yaml --force
surf --install-extension tamasfe.even-better-toml --force
surf --install-extension usernamehw.errorlens --force
surf --install-extension waderyan.gitblame --force
surf --install-extension wallabyjs.console-ninja --force
surf --install-extension wix.vscode-import-cost --force
surf --install-extension yoavbls.pretty-ts-errors --force
