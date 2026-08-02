#!/bin/sh

set -eu

echo "› setting up ssh configuration"

root_resolver=$HOME/.dotfiles-root
if [ ! -L "$root_resolver" ] || [ ! -x "$root_resolver" ]; then
  ssh_script_directory=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
  root_resolver=$ssh_script_directory/../dotfiles-root.symlink
fi

DOTFILES_ROOT=$("$root_resolver" "$0")
export DOTFILES_ROOT

SSH_DIR=$HOME/.ssh
DOTFILES_SSH=$DOTFILES_ROOT/ssh
SOURCE_CONFIG=$DOTFILES_SSH/config
SOURCE_LOCAL_CONFIG=$DOTFILES_SSH/config_local.example
SSH_CONFIG=$SSH_DIR/config
SSH_LOCAL_CONFIG=$SSH_DIR/config_local

fail() {
  echo "Error: $*" >&2
  exit 1
}

canonical_file_path() {
  canonical_input=$1
  canonical_directory=$(CDPATH='' cd -P -- "$(dirname -- "$canonical_input")" 2>/dev/null && pwd) || return 1
  printf '%s/%s\n' "$canonical_directory" "$(basename -- "$canonical_input")"
}

config_link_is_current() {
  [ -L "$SSH_CONFIG" ] || return 1

  current_target=$(readlink "$SSH_CONFIG") || return 1
  case "$current_target" in
    /*) ;;
    *) current_target=$SSH_DIR/$current_target ;;
  esac

  current_target=$(canonical_file_path "$current_target") || return 1
  expected_target=$(canonical_file_path "$SOURCE_CONFIG") || return 1
  [ "$current_target" = "$expected_target" ]
}

next_backup_path() {
  backup_base=$1.backup
  backup_path=$backup_base
  backup_number=1

  while [ -e "$backup_path" ] || [ -L "$backup_path" ]; do
    backup_path=$backup_base.$backup_number
    backup_number=$((backup_number + 1))
  done

  printf '%s\n' "$backup_path"
}

[ -f "$SOURCE_CONFIG" ] || fail "source config file not found: $SOURCE_CONFIG"
[ -f "$SOURCE_LOCAL_CONFIG" ] || fail "local config template not found: $SOURCE_LOCAL_CONFIG"

umask 077
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if config_link_is_current; then
  echo "  → ~/.ssh/config already linked"
else
  if [ -e "$SSH_CONFIG" ] || [ -L "$SSH_CONFIG" ]; then
    config_backup=$(next_backup_path "$SSH_CONFIG")
    mv "$SSH_CONFIG" "$config_backup"
    echo "  → backed up ~/.ssh/config to $config_backup"
  fi

  ln -s "$SOURCE_CONFIG" "$SSH_CONFIG"
  echo "  → linked ~/.ssh/config"
fi

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
