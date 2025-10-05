# Add VSCode to PATH
if [ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ]; then
    export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
fi

# Add VSCode Plugin to Brew bundle
if [ -d "/opt/homebrew/bin" ]; then
    export HOMEBREW_BREWFILE_VSCODE=1
fi
