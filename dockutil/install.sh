#!/usr/bin/env bash
# Minimal Dock setup

set -e

INSTALLER_ANCHOR=${BASH_SOURCE[0]}
# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$INSTALLER_ANCHOR")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring dock (minimal)"

# Validate dockutil is installed
if ! command -v dockutil >/dev/null 2>&1; then
  installer_error "dockutil is required but not installed"
  installer_hint "Install with: brew install dockutil"
  exit 1
fi

# Function to add app to dock if it exists
add_app_to_dock() {
  local app_path="$1"
  local app_name="$2"

  if [ -d "$app_path" ]; then
    if dockutil --add "$app_path" --no-restart >/dev/null 2>&1; then
      installer_success "Added $app_name"
    else
      installer_warn "Failed to add $app_name (may already be in dock)"
    fi
  else
    installer_warn "Skipping $app_name (not found at $app_path)"
  fi
}

# Clear everything
if ! dockutil --remove all --no-restart >/dev/null 2>&1; then
  installer_warn "Failed to clear dock"
fi

# Add Apps (only if they exist)
add_app_to_dock "/Applications/Ghostty.app" "Ghostty"
add_app_to_dock "/Applications/Google Chrome.app" "Google Chrome"
add_app_to_dock "/Applications/Zed.app" "Zed"
add_app_to_dock "/Applications/Onlook.app" "Onlook"
add_app_to_dock "/Applications/Obsidian.app" "Obsidian"
add_app_to_dock "/Applications/TablePlus.app" "TablePlus"
add_app_to_dock "/Applications/Lens.app" "Lens"
add_app_to_dock "/Applications/Postman.app" "Postman"
add_app_to_dock "/Applications/OrbStack.app" "OrbStack"
add_app_to_dock "/Applications/Figma.app" "Figma"
add_app_to_dock "/Applications/Spark Desktop.app" "Spark Desktop"
add_app_to_dock "/Applications/Spotify.app" "Spotify"
add_app_to_dock "/Applications/WhatsApp.app" "WhatsApp"
add_app_to_dock "/Applications/Bitwarden.app" "Bitwarden"
add_app_to_dock "/Applications/System Settings.app" "System Settings"

# === FOLDERS (others section = right of the divider, beside the trash) ===
# Add Workspace first, then Downloads so Downloads sits closest to the trash.
workspace_root=${WORKSPACE:-$HOME/Workspace}
if [ ! -d "$workspace_root" ]; then
  installer_note "$workspace_root not found, creating it"
  mkdir -p "$workspace_root/github.com"
fi
if dockutil --add "$workspace_root" --view list --display folder --section others --no-restart >/dev/null 2>&1; then
  installer_success "Added Workspace folder (others)"
fi

if [ -d "$HOME/Downloads" ]; then
  if dockutil --add "$HOME/Downloads" --view list --display folder --section others --no-restart >/dev/null 2>&1; then
    installer_success "Added Downloads folder (others, next to trash)"
  fi
else
  installer_warn "Downloads folder not found"
fi

# Restart Dock to apply changes
if killall Dock >/dev/null 2>&1; then
  installer_success "Dock restarted"
else
  installer_warn "Failed to restart Dock"
fi

installer_success "dock configured"
