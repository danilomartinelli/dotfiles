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

test_replace_generated() {
  local home source target

  home=$(scenario_tmpdir generated)
  source=$home/source
  target=$home/.config/tool/agents
  mkdir -p "$source" "$target"
  printf 'tracked\n' >"$source/entry.md"
  printf 'generated\n' >"$target/entry.md"

  invoke_link "$home" --policy replace-generated --label 'agents' "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'generated directory replaced'
  assert_contains "$home/stdout.log" 'Replaced generated agents'
  assert_contains "$target/entry.md" 'tracked'
  [[ ! -e $home/.config/tool/agents.backup ]] \
    || scenario_fail 'replace-generated left a backup of a directory'

  invoke_link "$home" --policy replace-generated --label 'agents' "$source" "$target"
  assert_contains "$home/stdout.log" 'agents already linked'
  assert_not_contains "$home/stdout.log" 'Replaced generated agents'

  rm "$target"
  printf 'generated file\n' >"$target"
  invoke_link "$home" --policy replace-generated --label 'agents' "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'generated file replaced'
  [[ ! -e $home/.config/tool/agents.backup ]] \
    || scenario_fail 'replace-generated left a backup of a file'

  rm "$target"
  ln -s "$home/elsewhere" "$target"
  invoke_link "$home" --policy replace-generated --label 'agents' "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'stale link replaced'

  rm "$target"
  invoke_link "$home" --policy replace-generated --label 'agents' "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'created when absent'
  assert_not_contains "$home/stdout.log" 'Replaced generated agents'
}

test_replace_generated_refuses_unsafe_targets() {
  local home source

  home=$(scenario_tmpdir generated-guard)
  source=$home/checkout/topic/agents
  mkdir -p "$source"
  printf 'tracked\n' >"$source/entry.md"

  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-generated "$source" "$home"
  assert_contains "$home/stderr.log" 'refusing to remove'
  [[ -f $source/entry.md ]] || scenario_fail 'home refusal destroyed the source'

  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-generated "$source" "$home/checkout"
  assert_contains "$home/stderr.log" 'it contains the source'
  [[ -f $source/entry.md ]] || scenario_fail 'ancestor refusal destroyed the source'

  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-generated "$source" /
  [[ -d /usr ]] || scenario_fail 'root refusal did not leave the filesystem intact'
}

# replace-confirmed destroys like replace-generated and says something
# different, because the caller is asserting an operator's decision rather
# than a claim about who writes the file.
test_replace_confirmed_destroys_and_shares_the_guard() {
  local home source target

  home=$(scenario_tmpdir confirmed)
  source=$home/checkout/topic/settings
  target=$home/.config/tool/settings
  mkdir -p "$source" "$home/.config/tool"
  printf 'tracked\n' >"$source/entry.md"
  printf 'hand written\n' >"$target"

  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$target"
  assert_equal "$source" "$(readlink "$target")" 'confirmed target replaced'
  assert_contains "$home/stdout.log" 'Replaced settings as confirmed'
  assert_not_contains "$home/stdout.log" 'generated'
  [[ ! -e $home/.config/tool/settings.backup ]] \
    || scenario_fail 'replace-confirmed left a backup'

  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$target"
  assert_contains "$home/stdout.log" 'settings already linked'

  # The same three refusals, because they do not depend on the caller's reason.
  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-confirmed "$source" "$home"
  assert_contains "$home/stderr.log" 'refusing to remove'
  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-confirmed "$source" "$home/checkout"
  assert_contains "$home/stderr.log" 'it contains the source'
  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-confirmed "$source" /
  [[ -f $source/entry.md ]] || scenario_fail 'a refusal destroyed the source'
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
scenario_run 'replace-generated discards generated targets without a backup' \
  test_replace_generated
scenario_run 'replace-generated refuses to remove unsafe targets' \
  test_replace_generated_refuses_unsafe_targets
scenario_run 'replace-confirmed destroys without a backup and shares the guard' \
  test_replace_confirmed_destroys_and_shares_the_guard
scenario_run 'missing source fails' test_missing_source_fails
scenario_finish
