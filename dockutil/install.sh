#!/bin/sh
# Minimal Dock setup

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› configuring dock (minimal)"

# Validate dockutil is installed
if ! command -v dockutil >/dev/null 2>&1; then
  echo "Error: dockutil is required but not installed." >&2
  echo "  Install with: brew install dockutil" >&2
  exit 1
fi

# Function to add app to dock if it exists
add_app_to_dock() {
  local app_path="$1"
  local app_name="$2"

  if [ -d "$app_path" ]; then
    if dockutil --add "$app_path" --no-restart >/dev/null 2>&1; then
      echo "  ✓ Added $app_name"
    else
      echo "  ⚠️  Failed to add $app_name (may already be in dock)" >&2
    fi
  else
    echo "  ⚠️  Skipping $app_name (not found at $app_path)" >&2
  fi
}

# Clear everything
if ! dockutil --remove all --no-restart >/dev/null 2>&1; then
  echo "Warning: Failed to clear dock" >&2
fi

# Add Apps (only if they exist)
add_app_to_dock "/Applications/Google Chrome.app" "Google Chrome"
add_app_to_dock "/Applications/ChatGPT.app" "ChatGPT"
add_app_to_dock "/Applications/Cursor.app" "Cursor"
add_app_to_dock "/Applications/TablePlus.app" "TablePlus"
add_app_to_dock "/Applications/Lens.app" "Lens"
add_app_to_dock "/Applications/Postman.app" "Postman"
add_app_to_dock "/Applications/Warp.app" "Warp"
add_app_to_dock "/Applications/OrbStack.app" "OrbStack"
add_app_to_dock "/Applications/Notion.app" "Notion"
add_app_to_dock "/Applications/Figma.app" "Figma"
add_app_to_dock "/Applications/Spark Desktop.app" "Spark Desktop"
add_app_to_dock "/Applications/Spotify.app" "Spotify"
add_app_to_dock "/Applications/WhatsApp.app" "WhatsApp"
add_app_to_dock "/Applications/Bitwarden.app" "Bitwarden"
add_app_to_dock "/Applications/System Settings.app" "System Settings"

# === FOLDERS SECTION (after the | separator) ===
# Add Downloads folder
if [ -d "$HOME/Downloads" ]; then
  if dockutil --add "$HOME/Downloads" --view list --display folder --section others --no-restart >/dev/null 2>&1; then
    echo "  ✓ Added Downloads folder"
  fi
else
  echo "  ⚠️  Downloads folder not found" >&2
fi

# Add Code folder (if it exists)
if [ -d "$HOME/Code" ]; then
  if dockutil --add "$HOME/Code" --view list --display folder --section others --no-restart >/dev/null 2>&1; then
    echo "  ✓ Added Code folder"
  fi
else
  echo "  → ~/Code folder not found, creating it"
  mkdir -p "$HOME/Code"
  if dockutil --add "$HOME/Code" --view list --display folder --section others --no-restart >/dev/null 2>&1; then
    echo "  ✓ Added Code folder"
  fi
fi

# Restart Dock to apply changes
if killall Dock >/dev/null 2>&1; then
  echo "✓ Dock restarted"
else
  echo "Warning: Failed to restart Dock" >&2
fi

echo "✓ dock configured"
