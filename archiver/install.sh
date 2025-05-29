#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting Archiver as default app for compressed files"

# Define Archiver's bundle ID
ARCHIVER_BUNDLE="com.incrediblebee.Archiver"

# List of compressed file extensions
EXTENSIONS=".zip .rar .7z .tar .gz .bz2 .xz .tgz .tbz2"

# Set default app for each extension
for ext in $EXTENSIONS; do
  duti -s $ARCHIVER_BUNDLE $ext all
done

echo "✓ Archiver set as default for compressed files"
