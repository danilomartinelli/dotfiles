#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Ghostty configuration"

CONFIG_DIR="$HOME/.config/ghostty"

mkdir -p "$CONFIG_DIR"

installer_link_config --label "Ghostty config" "$TOPIC_DIR/config" "$CONFIG_DIR/config"

# Register Ghostty as the default handler for Unix executables (idempotent).
if [ ! -d "/Applications/Ghostty.app" ]; then
  installer_warn "Ghostty not found at /Applications/Ghostty.app; skipping default terminal handler"
elif defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers 2>/dev/null | grep -q "com.mitchellh.ghostty"; then
  installer_success "Ghostty already the default terminal handler"
elif defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{LSHandlerContentType=public.unix-executable;LSHandlerRoleAll=com.mitchellh.ghostty;}' 2>/dev/null; then
  installer_success "Ghostty set as default terminal handler"
else
  installer_warn "Failed to set Ghostty as default terminal handler"
  installer_hint "You may need to set it manually in System Settings"
fi

installer_success "Ghostty configured"
