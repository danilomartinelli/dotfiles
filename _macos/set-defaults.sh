#!/bin/sh
# macOS System Defaults for Developers
# Run ./set-defaults.sh and you'll be good to go.

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: This script is only for macOS" >&2
  exit 1
fi

# === KEYBOARD & INPUT ===
# Disable press-and-hold for keys in favor of key repeat
defaults write -g ApplePressAndHoldEnabled -bool false

# Change `fn` behavior
defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true

# Set a really fast key repeat
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 10

# Full keyboard access: Tab moves focus between all controls
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# Disable auto-correct and auto-capitalization
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# === TRACKPAD ===
# Tap to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# === FINDER ===
# Always open everything in Finder's list view
defaults write com.apple.finder FXPreferredViewStyle Nlsv

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show path bar in Finder
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar in Finder
defaults write com.apple.finder ShowStatusBar -bool true

# Show the full POSIX path in the window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Keep folders first when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Allow quitting Finder with Cmd+Q
defaults write com.apple.finder QuitMenuItem -bool true

# Show volumes on Desktop
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true

# Disable .DS_Store files on network and USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# New Finder windows show home directory
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/"

# Expand save and print panels by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# === DOCK ===
# Set Dock position (left, bottom, or right)
defaults write com.apple.dock orientation -string "bottom"

# Set Dock icon size (in pixels)
defaults write com.apple.dock tilesize -int 48

# Automatically hide and show the Dock, without delay
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.4

# Disable the launch animation
defaults write com.apple.dock launchanim -bool false

# Don't show recent applications in Dock
defaults write com.apple.dock show-recents -bool false

# Disable all hot corners (set to 1 = no action)
defaults write com.apple.dock wvous-tl-corner -int 1
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int 1
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-bl-corner -int 1
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-corner -int 1
defaults write com.apple.dock wvous-br-modifier -int 0

# === MISSION CONTROL ===
# Don't automatically rearrange spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false

# Group windows by application in Mission Control
defaults write com.apple.dock expose-group-by-app -bool true

# === SECURITY & PRIVACY ===
# Use AirDrop over every interface
defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true

# === MENU BAR (Control Center) ===
# Show battery percentage
defaults write com.apple.controlcenter BatteryShowPercentage -bool true

# Menu bar clock: show seconds and day of week
defaults write com.apple.menuextra.clock ShowSeconds -bool true
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true

# === TIME MACHINE ===
# Don't offer new disks for backup
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# === NETWORK ===
# Use Google DNS servers (requires admin privileges)
if command -v networksetup >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null || sudo -v; then
    if sudo networksetup -setdnsservers Wi-Fi 8.8.8.8 8.8.4.4 2>/dev/null; then
      echo "  ✓ DNS servers configured"
    else
      echo "  Warning: Failed to set DNS servers (may require admin privileges)" >&2
    fi
  else
    echo "  Warning: Skipping DNS configuration (sudo access required)" >&2
  fi
else
  echo "  Warning: networksetup not found, skipping DNS configuration" >&2
fi

# === DEVELOPMENT ENVIRONMENT ===
# Show ~/Library folder (for development)
if [ -d "$HOME/Library" ]; then
  if chflags nohidden ~/Library 2>/dev/null; then
    xattr -d com.apple.FinderInfo ~/Library 2>/dev/null || true
    echo "  ✓ Library folder is now visible"
  else
    echo "  Warning: Failed to show Library folder" >&2
  fi
fi

# Restart services last so every domain above is reloaded. Keyboard settings
# apply fully only after logout/login.
echo "  → Restarting system services..."
killall Finder Dock SystemUIServer ControlCenter ControlStrip cfprefsd 2>/dev/null || true
echo "  ✓ Services restarted (log out to apply keyboard settings)"
