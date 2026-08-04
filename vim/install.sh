#!/bin/sh

set -e

echo "› setting up Neovim configuration"

TOPIC_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
DOTFILES_ROOT=$(CDPATH='' cd -P -- "$TOPIC_DIR/.." && pwd)
CONFIG_DIR="$HOME/.config/nvim"
LINK_CONFIG="$DOTFILES_ROOT/_scripts/link-config"

mkdir -p "$CONFIG_DIR"

"$LINK_CONFIG" --label "Neovim init" "$TOPIC_DIR/init.vim" "$CONFIG_DIR/init.vim"

echo "✓ Neovim configured"
