#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up Zed configuration"

CONFIG_DIR="$HOME/.config/zed"

mkdir -p "$CONFIG_DIR"

installer_link_config --label "Zed settings" \
  "$TOPIC_DIR/settings.json" "$CONFIG_DIR/settings.json"

installer_link_config --label "Zed keymap" \
  "$TOPIC_DIR/keymap.json" "$CONFIG_DIR/keymap.json"

ZED_BUNDLE="dev.zed.Zed"

installer_require_app Zed zed /Applications/Zed.app

installer_skip_if_applied zed-associations "file associations" "Zed configured"

installer_optional_command duti "duti is required to set Zed as the default text editor"

# Common source/text extensions opened in Zed by default.
# Role "editor" is used throughout — never "all" — so that .html/.htm do not
# claim the viewer role that macOS maps to the default web browser, which would
# trigger the system confirmation dialog asking to change the default browser.
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
  if ! duti -s "$ZED_BUNDLE" "$ext" editor 2>/dev/null; then
    failed=$((failed + 1))
  fi
done

# Broad UTIs for plain text / source when Launch Services supports them.
# public.html is intentionally omitted: claiming it with any role other than
# "editor" can prompt macOS to change the default browser.
for uti in public.plain-text public.source-code public.script public.shell-script public.python-script public.ruby-script public.json public.yaml public.xml net.daringfireball.markdown; do
  duti -s "$ZED_BUNDLE" "$uti" editor 2>/dev/null || true
done

installer_mark_applied zed-associations

if [ "$failed" -eq 0 ]; then
  installer_success "Zed set as default app for tracked text/source extensions"
else
  installer_warn "Some Zed file associations could not be configured ($failed failed)"
fi

installer_success "Zed configured"
