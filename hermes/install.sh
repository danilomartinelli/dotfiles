#!/bin/sh

set -e

echo "› setting up Hermes Agent"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
mkdir -p "$HERMES_HOME"

if command -v hermes >/dev/null 2>&1; then
  echo "  ✓ hermes CLI available"
else
  echo "  → Install Hermes with: brew install hermes-agent"
fi

echo "  → Put provider API keys in ~/.localrc (see .localrc.example)"
echo "  → Configure provider/model with: hermes model"
echo "  → Or run the full wizard with: hermes setup"
echo "✓ Hermes Agent configured"
