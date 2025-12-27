#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting Archiver as default app for compressed files"

# Validate duti is installed
if ! command -v duti >/dev/null 2>&1; then
  echo "Error: duti is required but not installed." >&2
  echo "  Install with: brew install duti" >&2
  exit 1
fi

# Define Archiver's bundle ID
ARCHIVER_BUNDLE="com.incrediblebee.Archiver"

# Check if Archiver app exists
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "/Applications/Archiver.app/Contents/Info.plist" 2>/dev/null | grep -q "$ARCHIVER_BUNDLE"; then
  echo "Warning: Archiver app not found at /Applications/Archiver.app" >&2
  echo "  Skipping default app configuration. Install Archiver from Mac App Store." >&2
  exit 0
fi

# List of compressed file extensions
EXTENSIONS=".zip .rar .7z .tar .gz .bz2 .xz .tgz .tbz2"

# Set default app for each extension
failed=0
for ext in $EXTENSIONS; do
  if ! duti -s "$ARCHIVER_BUNDLE" "$ext" all 2>/dev/null; then
    echo "Warning: Failed to set Archiver as default for $ext" >&2
    failed=$((failed + 1))
  fi
done

if [ $failed -eq 0 ]; then
  echo "✓ Archiver set as default for compressed files"
else
  echo "Warning: Some file types could not be configured ($failed failed)" >&2
  exit 1
fi
