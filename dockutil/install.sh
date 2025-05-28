#!/bin/sh
# Minimal Dock setup

echo "› configuring dock (minimal)"

# Clear everything
dockutil --remove all --no-restart

# Add VS Code
dockutil --add "/Applications/Visual Studio Code.app" --no-restart

# Add OrbStack
dockutil --add "/Applications/OrbStack.app" --no-restart

# Restart Dock to apply changes
killall Dock

echo "✓ dock configured with VS Code and OrbStack"
