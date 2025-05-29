#!/bin/sh

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting Ghostty as default terminal app for shell files"

GHOSTTY_BUNDLE="com.mitchellh.ghostty"
EXTENSIONS=".sh .command .terminal"

for ext in $EXTENSIONS; do
  duti -s $GHOSTTY_BUNDLE $ext all
done

echo "✓ Ghostty set as default for terminal-related files"
