#!/bin/sh

set -e

# Only run on macOS
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

echo "› setting up Zed configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
DOTFILES_ROOT=$(CDPATH='' cd -P -- "$TOPIC_DIR/.." && pwd)
CONFIG_DIR="$HOME/.config/zed"
LINK_CONFIG="$DOTFILES_ROOT/_scripts/link-config"

mkdir -p "$CONFIG_DIR"

"$LINK_CONFIG" --label "Zed settings" \
  "$TOPIC_DIR/settings.json" "$CONFIG_DIR/settings.json"

ZED_BUNDLE="dev.zed.Zed"
ZED_APP="/Applications/Zed.app"

if [ ! -d "$ZED_APP" ]; then
  echo "Warning: Zed not found at $ZED_APP; skipping default-app associations" >&2
  echo "✓ Zed configuration linked (install Zed to register file associations)"
  exit 0
fi

if ! command -v duti >/dev/null 2>&1; then
  echo "Warning: duti is required to set Zed as the default text editor" >&2
  echo "  Install with: brew install duti" >&2
  exit 0
fi

# Common source/text extensions opened in Zed by default.
EXTENSIONS="
.txt .md .markdown .mdx .rst .adoc
.json .jsonc .json5 .toml .yaml .yml .xml .csv .tsv
.js .jsx .mjs .cjs .ts .tsx .mts .cts
.css .scss .sass .less .html .htm .svg
.py .rb .go .rs .java .kt .kts .swift
.sh .bash .zsh .fish .ps1
.c .h .cpp .hpp .cc .m .mm
.ex .exs .erl .hrl .lua .php .sql .graphql .gql
.env .gitignore .editorconfig .dockerignore
"

failed=0
for ext in $EXTENSIONS; do
  if ! duti -s "$ZED_BUNDLE" "$ext" all 2>/dev/null; then
    failed=$((failed + 1))
  fi
done

# Broad UTIs for plain text / source when Launch Services supports them.
for uti in public.plain-text public.source-code public.script public.shell-script public.python-script public.ruby-script public.json public.yaml public.xml net.daringfireball.markdown; do
  duti -s "$ZED_BUNDLE" "$uti" all 2>/dev/null || true
done

if [ "$failed" -eq 0 ]; then
  echo "  ✓ Zed set as default app for tracked text/source extensions"
else
  echo "Warning: Some Zed file associations could not be configured ($failed failed)" >&2
fi

echo "✓ Zed configured"
