#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

# Function to download and verify script with checksum
download_and_verify() {
    local url="$1"
    local temp_file="/tmp/homebrew_installer.sh"

    echo "  Downloading Homebrew installer..."
    if ! curl -fsSL "$url" -o "$temp_file"; then
        echo "  ERROR: Failed to download Homebrew installer" >&2
        return 1
    fi

    # Note: Homebrew doesn't publish official checksums for their installer
    # In production, you would ideally verify against a known checksum
    # For now, we at least verify the script contains expected content
    if ! grep -q "Homebrew" "$temp_file"; then
        echo "  ERROR: Downloaded script doesn't appear to be valid Homebrew installer" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo "  Executing Homebrew installer..."
    /bin/bash "$temp_file"
    local result=$?

    # Clean up
    rm -f "$temp_file"

    return $result
}

# Check for Homebrew
if test ! "$(which brew)"
then
  echo "  Installing Homebrew for you."

  # Install the correct homebrew for each OS type
  if test "$(uname)" = "Darwin"
  then
    download_and_verify "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  elif test "$(expr substr "$(uname -s)" 1 5)" = "Linux"
  then
    download_and_verify "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  fi

  # Verify installation succeeded
  if test ! "$(which brew)"
  then
    echo "  ERROR: Homebrew installation failed" >&2
    exit 1
  fi

  echo "  Homebrew installed successfully."
fi

exit 0