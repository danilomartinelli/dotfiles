#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-link-config-tests

LINK_CONFIG=$REPOSITORY_ROOT/_scripts/link-config

invoke_link() {
  local home=$1
  shift
  scenario_capture "$home" env HOME="$home" "$LINK_CONFIG" "$@"
}

test_replace_with_backup_and_idempotent() {
  local home source target

  home=$(scenario_tmpdir home)
  source=$home/source.conf
  target=$home/.config/app/config
  mkdir -p "$(dirname "$target")"
  printf 'tracked\n' >"$source"

  invoke_link "$home" --label 'app config' "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'fresh link target'
  assert_contains "$home/stdout.log" 'app config linked'

  invoke_link "$home" --label 'app config' "$source" "$target"
  assert_contains "$home/stdout.log" 'app config already linked'
  [[ ! -e $home/.config/app/config.backup ]]

  printf 'local\n' >"$target.regular"
  rm "$target"
  mv "$target.regular" "$target"
  invoke_link "$home" --label 'app config' "$source" "$target"
  assert_contains "$home/.config/app/config.backup" 'local'
  assert_equal "$source" "$(readlink "$target")" 'relinked after backup'

  printf 'local2\n' >"$home/.config/app/config.real"
  rm "$target"
  mv "$home/.config/app/config.real" "$target"
  invoke_link "$home" --label 'app config' "$source" "$target"
  assert_contains "$home/stderr.log" 'leaving app config untouched'
  assert_contains "$target" 'local2'
}

test_preserve_existing() {
  local home source target

  home=$(scenario_tmpdir preserve)
  source=$home/source.json
  target=$home/.orbstack/config/docker.json
  mkdir -p "$(dirname "$target")"
  printf 'tracked\n' >"$source"
  printf 'local\n' >"$target"

  invoke_link "$home" --policy preserve-existing --label 'docker.json' "$source" "$target"
  assert_contains "$target" 'local'
  assert_contains "$home/stdout.log" 'kept'
  [[ ! -L $target ]]

  rm "$target"
  invoke_link "$home" --policy preserve-existing --label 'docker.json' "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'created when absent'
}

test_numbered_backup() {
  local home source target

  home=$(scenario_tmpdir numbered)
  source=$home/source
  target=$home/.ssh/config
  mkdir -p "$(dirname "$target")"
  printf 'tracked\n' >"$source"
  printf 'backup0\n' >"$target.backup"
  printf 'original\n' >"$target"

  invoke_link "$home" --policy numbered-backup --label 'ssh config' "$source" "$target"
  assert_contains "$home/.ssh/config.backup" 'backup0'
  assert_contains "$home/.ssh/config.backup.1" 'original'
  assert_equal "$source" "$(readlink "$target")" 'numbered replacement'
}

test_missing_source_fails() {
  local home

  home=$(scenario_tmpdir missing)
  if invoke_link "$home" "$home/missing" "$home/target"; then
    return 1
  fi
  assert_contains "$home/stderr.log" 'source not found'
}

scenario_run 'replace-with-backup links, backs up once, and stays idempotent' test_replace_with_backup_and_idempotent
scenario_run 'preserve-existing keeps local files' test_preserve_existing
scenario_run 'numbered-backup uses free backup suffixes' test_numbered_backup
scenario_run 'missing source fails' test_missing_source_fails
scenario_finish
