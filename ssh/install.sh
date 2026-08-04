#!/bin/sh

set -eu

echo "› setting up ssh configuration"

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/adapter-checkout.sh"

SSH_DIR=$HOME/.ssh
DOTFILES_SSH=$DOTFILES_ROOT/ssh
SOURCE_CONFIG=$DOTFILES_SSH/config
SOURCE_LOCAL_CONFIG=$DOTFILES_SSH/config_local.example
SSH_CONFIG=$SSH_DIR/config
SSH_LOCAL_CONFIG=$SSH_DIR/config_local
LINK_CONFIG=$DOTFILES_ROOT/_scripts/link-config

fail() {
  echo "Error: $*" >&2
  exit 1
}

[ -f "$SOURCE_CONFIG" ] || fail "source config file not found: $SOURCE_CONFIG"
[ -f "$SOURCE_LOCAL_CONFIG" ] || fail "local config template not found: $SOURCE_LOCAL_CONFIG"

umask 077
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

"$LINK_CONFIG" --policy numbered-backup --label '~/.ssh/config' \
  "$SOURCE_CONFIG" "$SSH_CONFIG"

if [ ! -e "$SSH_LOCAL_CONFIG" ] && [ ! -L "$SSH_LOCAL_CONFIG" ]; then
  cp "$SOURCE_LOCAL_CONFIG" "$SSH_LOCAL_CONFIG"
  echo "  → created ~/.ssh/config_local (customize it for your servers)"
elif [ ! -f "$SSH_LOCAL_CONFIG" ]; then
  fail "$SSH_LOCAL_CONFIG must be a regular file or a symlink to one"
fi

chmod 600 "$SSH_LOCAL_CONFIG"

for identity_file in "$SSH_DIR"/id_*; do
  [ -f "$identity_file" ] || continue
  case "$identity_file" in
    *.pub) chmod 644 "$identity_file" ;;
    *) chmod 600 "$identity_file" ;;
  esac
done

echo "✓ ssh configuration complete"
