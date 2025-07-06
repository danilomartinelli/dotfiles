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

surf --install-extension aaron-bond.better-comments
surf --install-extension bradlc.vscode-tailwindcss
surf --install-extension christian-kohler.path-intellisense
surf --install-extension csstools.postcss
surf --install-extension dbaeumer.vscode-eslint
surf --install-extension eamodio.gitlens
surf --install-extension esbenp.prettier-vscode
surf --install-extension figma.figma-vscode-extension
surf --install-extension formulahendry.auto-close-tag
surf --install-extension formulahendry.auto-rename-tag
surf --install-extension jock.svg
surf --install-extension mechatroner.rainbow-csv
surf --install-extension mikestead.dotenv
surf --install-extension monokai.theme-monokai-pro-vscode
surf --install-extension ms-vscode.vscode-typescript-next
surf --install-extension redhat.vscode-yaml
surf --install-extension tamasfe.even-better-toml
surf --install-extension usernamehw.errorlens
surf --install-extension waderyan.gitblame
surf --install-extension wallabyjs.console-ninja
surf --install-extension wix.vscode-import-cost
surf --install-extension yoavbls.pretty-ts-errors

surf --update-extensions
