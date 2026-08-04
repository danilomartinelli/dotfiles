#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-link-dotfiles-tests

make_repo() {
  local repo
  repo=$(scenario_tmpdir repo)
  mkdir -p "$repo/_scripts" "$repo/sample" "$repo/bin" "$repo/home"
  cp "$REPOSITORY_ROOT/_scripts/link-dotfiles" "$repo/_scripts/link-dotfiles"
  cp "$REPOSITORY_ROOT/_scripts/topic-catalog" "$repo/_scripts/topic-catalog"
  cp "$REPOSITORY_ROOT/dotfiles-root.symlink" "$repo/dotfiles-root.symlink"
  chmod +x "$repo/_scripts/link-dotfiles" "$repo/_scripts/topic-catalog" "$repo/dotfiles-root.symlink"
  printf '%s\n' 'localrc' >"$repo/.localrc"
  printf '%s\n' 'config body' >"$repo/sample/config.symlink"
  printf '%s\n' 'ignored' >"$repo/bin/reserved.symlink"
  printf '%s\n' "$repo"
}

invoke_linker() {
  local repo=$1
  shift
  scenario_capture "$repo" env \
    HOME="$repo/home" \
    DOTFILES_ROOT="$repo" \
    "$repo/_scripts/link-dotfiles" "$@"
}

test_batch_link_and_idempotent() {
  local repo

  repo=$(make_repo)
  invoke_linker "$repo" --batch overwrite
  [[ -L $repo/home/.localrc ]]
  [[ -L $repo/home/.config ]]
  [[ ! -e $repo/home/.reserved ]]
  assert_contains "$repo/stdout.log" 'linked'

  invoke_linker "$repo" --batch overwrite
  assert_contains "$repo/stdout.log" 'already linked'
}

test_batch_backup_and_skip() {
  local repo

  repo=$(make_repo)
  printf 'existing\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch backup
  assert_contains "$repo/home/.config.backup" 'existing'
  [[ -L $repo/home/.config ]]

  repo=$(make_repo)
  printf 'keep\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch skip
  assert_contains "$repo/home/.config" 'keep'
  [[ ! -L $repo/home/.config ]]
}

scenario_run 'batch overwrite links localrc and topic symlinks' test_batch_link_and_idempotent
scenario_run 'batch backup and skip honor conflict policy' test_batch_backup_and_skip
scenario_finish
