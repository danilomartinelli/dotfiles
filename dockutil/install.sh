#!/bin/sh
# Minimal Dock setup

echo "› configuring dock (minimal)"

# Clear everything
dockutil --remove all --no-restart

# Add Zen
dockutil --add "/Applications/Zen.app" --no-restart

# Add VS Code
dockutil --add "/Applications/Visual Studio Code.app" --no-restart

# Add Ghostty
dockutil --add "/Applications/Ghostty.app" --no-restart

# Add TablePlus
dockutil --add "/Applications/TablePlus.app" --no-restart

# Add Lens
dockutil --add "/Applications/Lens.app" --no-restart

# Add Apidog
dockutil --add "/Applications/Apidog.app" --no-restart

# Add Spark Desktop
dockutil --add "/Applications/Spark Desktop.app" --no-restart

# Add Spotify
dockutil --add "/Applications/Spotify.app" --no-restart

# Add System Settings
dockutil --add "/Applications/System Settings.app" --no-restart

# === FOLDERS SECTION (after the | separator) ===
# Add Downloads folder
dockutil --add "$HOME/Downloads" --view list --display folder --section others --no-restart

# Add Code folder (if it exists)
if [ -d "$HOME/Code" ]; then
    dockutil --add "$HOME/Code" --view list --display folder --section others --no-restart
else
    echo "  → ~/Code folder not found, creating it"
    mkdir -p "$HOME/Code"
    dockutil --add "$HOME/Code" --view list --display folder --section others --no-restart
fi

# Restart Dock to apply changes
killall Dock

echo "✓ dock configured with VS Code and OrbStack"
