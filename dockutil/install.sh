#!/bin/sh
# Minimal Dock setup

echo "› configuring dock (minimal)"

# Clear everything
dockutil --remove all --no-restart

# Add Apps
dockutil --add "/Applications/Apps.app" --no-restart

# Add Chrome
dockutil --add "/Applications/Google Chrome.app" --no-restart

# Add ChatGPT
dockutil --add "/Applications/ChatGPT.app" --no-restart

# Add IDE
dockutil --add "/Applications/Cursor.app" --no-restart

# Add TablePlus
dockutil --add "/Applications/TablePlus.app" --no-restart

# Add Lens
dockutil --add "/Applications/Lens.app" --no-restart

# Add Apidog
dockutil --add "/Applications/Apidog.app" --no-restart

# Add iTerm
dockutil --add "/Applications/iTerm.app" --no-restart

# Add OrbStack
dockutil --add "/Applications/OrbStack.app" --no-restart

# Add Figma
dockutil --add "/Applications/Figma.app" --no-restart

# Add Linear
dockutil --add "/Applications/Linear.app" --no-restart

# Add Obsidian
dockutil --add "/Applications/Obsidian.app" --no-restart

# Add Spark Desktop
dockutil --add "/Applications/Spark Desktop.app" --no-restart

# Add Spotify
dockutil --add "/Applications/Spotify.app" --no-restart

# Add WhatsApp
dockutil --add "/Applications/WhatsApp.app" --no-restart

# Add Bitwarden
dockutil --add "/Applications/Bitwarden.app" --no-restart

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

echo "✓ dock configured"
