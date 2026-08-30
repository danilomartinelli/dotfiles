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
  cp "$REPOSITORY_ROOT/_scripts/link-config" "$repo/_scripts/link-config"
  cp "$REPOSITORY_ROOT/_scripts/output.sh" "$repo/_scripts/output.sh"
  cp "$REPOSITORY_ROOT/_scripts/topic-catalog" "$repo/_scripts/topic-catalog"
  cp "$REPOSITORY_ROOT/dotfiles-root.symlink" "$repo/dotfiles-root.symlink"
  chmod +x "$repo/_scripts/link-dotfiles" "$repo/_scripts/link-config" \
    "$repo/_scripts/topic-catalog" "$repo/dotfiles-root.symlink"
  printf '%s\n' 'localrc' >"$repo/.localrc"
  printf '%s\n' 'config body' >"$repo/sample/config.symlink"
  mkdir -p "$repo/sample/bundle.symlink"
  printf '%s\n' 'directory config' >"$repo/sample/bundle.symlink/config.json"
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

assert_symlink() {
  [[ -L $1 ]] || scenario_fail "$2 (expected a symlink at $1)"
}

assert_absent() {
  [[ ! -e $1 && ! -L $1 ]] || scenario_fail "$2 (unexpected path $1)"
}

test_batch_link_and_idempotent() {
  local repo

  repo=$(make_repo)
  invoke_linker "$repo" --batch overwrite
  assert_symlink "$repo/home/.localrc" 'localrc link'
  assert_symlink "$repo/home/.bundle" 'directory symlink entry'
  assert_symlink "$repo/home/.config" 'file symlink entry'
  assert_contains "$repo/home/.bundle/config.json" 'directory config'
  assert_absent "$repo/home/.reserved" 'reserved directory entry is not linked'
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
  assert_symlink "$repo/home/.config" 'backup policy still links'

  repo=$(make_repo)
  printf 'keep\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch skip
  assert_contains "$repo/home/.config" 'keep'
  [[ ! -L $repo/home/.config ]] \
    || scenario_fail 'skip replaced a local file with a link'
  assert_not_contains "$repo/stdout.log" 'linked to'
}

# The linker refuses to write over a backup it did not make. This module used
# to `mv` onto the same path unconditionally, so a second conflicting run
# destroyed whatever the first run had preserved.
test_an_existing_backup_is_never_clobbered() {
  local repo

  repo=$(make_repo)
  printf 'first\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch backup
  assert_contains "$repo/home/.config.backup" 'first'

  rm -f "$repo/home/.config"
  printf 'second\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch backup
  assert_contains "$repo/home/.config.backup" 'first'
  assert_contains "$repo/home/.config" 'second'
  assert_contains "$repo/stderr.log" 'leaving'
}

# overwrite destroys without a backup, so it inherits the linker's guard
# rather than running an unattended rm -rf on whatever it was handed. The
# catalog only ever yields $HOME/.<name> targets, so the guard is unreachable
# from here by construction; what this pins is that the removal is the
# linker's to perform at all.
test_removal_belongs_to_the_linker() {
  local repo status=0

  repo=$(make_repo)

  # Overwriting a real local file reports through the linker's voice, which is
  # what shows the removal crossed the seam rather than happening here.
  printf 'local\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch overwrite
  assert_contains "$repo/stdout.log" 'as confirmed'
  assert_symlink "$repo/home/.config" 'overwrite still links'
  assert_absent "$repo/home/.config.backup" 'overwrite leaves no backup'

  scenario_capture "$repo" env \
    HOME="$repo/home" \
    DOTFILES_ROOT="$repo" \
    "$repo/_scripts/link-config" --policy replace-confirmed \
    "$repo/sample/config.symlink" "$repo/home" || status=$?

  assert_equal 2 "$status" 'replace-confirmed refuses the home directory'
  assert_contains "$repo/stderr.log" 'refusing to remove'
  [[ -d $repo/home ]] || scenario_fail 'the home directory was removed'
}

scenario_run 'batch overwrite links localrc and topic symlinks' test_batch_link_and_idempotent
scenario_run 'batch backup and skip honor conflict policy' test_batch_backup_and_skip
scenario_run 'an existing backup is never clobbered' \
  test_an_existing_backup_is_never_clobbered
scenario_run 'every removal belongs to the config linker' \
  test_removal_belongs_to_the_linker
scenario_finish
