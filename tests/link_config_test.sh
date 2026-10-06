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
  local home source destination

  home=$(scenario_tmpdir home)
  source=$home/source.conf
  destination=$home/.config/app/config
  mkdir -p "$(dirname "$destination")"
  printf 'tracked\n' >"$source"

  invoke_link "$home" --label 'app config' "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'fresh link destination'
  assert_contains "$home/stdout.log" 'app config linked'

  invoke_link "$home" --label 'app config' "$source" "$destination"
  assert_contains "$home/stdout.log" 'app config already linked'
  [[ ! -e $home/.config/app/config.backup ]]

  printf 'local\n' >"$destination.regular"
  rm "$destination"
  mv "$destination.regular" "$destination"
  invoke_link "$home" --label 'app config' "$source" "$destination"
  assert_contains "$home/.config/app/config.backup" 'local'
  assert_equal "$source" "$(readlink "$destination")" 'relinked after backup'

  # The one backup slot this policy owns is taken, so the link cannot be made.
  # Exiting zero here reported a link that does not exist all the way up to
  # setup's [ OK ], which is why this asserts the status and not just the text.
  printf 'local2\n' >"$home/.config/app/config.real"
  rm "$destination"
  mv "$home/.config/app/config.real" "$destination"
  assert_fails_with_status 1 invoke_link "$home" --label 'app config' "$source" "$destination"
  assert_contains "$home/stderr.log" 'cannot link app config'
  assert_contains "$home/stderr.log" 'Move or remove'
  assert_contains "$destination" 'local2'
  assert_contains "$home/.config/app/config.backup" 'local'
  [[ ! -L $destination ]] || scenario_fail 'refused link replaced the destination anyway'
}

test_preserve_existing() {
  local home source destination

  home=$(scenario_tmpdir preserve)
  source=$home/source.json
  destination=$home/.orbstack/config/docker.json
  mkdir -p "$(dirname "$destination")"
  printf 'tracked\n' >"$source"
  printf 'local\n' >"$destination"

  invoke_link "$home" --policy preserve-existing --label 'docker.json' "$source" "$destination"
  assert_contains "$destination" 'local'
  assert_contains "$home/stdout.log" 'kept'
  [[ ! -L $destination ]]

  rm "$destination"
  invoke_link "$home" --policy preserve-existing --label 'docker.json' "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'created when absent'
}

test_numbered_backup() {
  local home source destination

  home=$(scenario_tmpdir numbered)
  source=$home/source
  destination=$home/.ssh/config
  mkdir -p "$(dirname "$destination")"
  printf 'tracked\n' >"$source"
  printf 'backup0\n' >"$destination.backup"
  printf 'original\n' >"$destination"

  invoke_link "$home" --policy numbered-backup --label 'ssh config' "$source" "$destination"
  assert_contains "$home/.ssh/config.backup" 'backup0'
  assert_contains "$home/.ssh/config.backup.1" 'original'
  assert_equal "$source" "$(readlink "$destination")" 'numbered replacement'
}

# replace-confirmed carries an operator's decision rather than a claim about
# who writes the file, so it destroys whatever the destination holds —
# directory, file, or wrong link — without a backup, and says only that it was
# confirmed.
test_replace_confirmed_destroys_without_a_backup() {
  local home source destination

  home=$(scenario_tmpdir confirmed)
  source=$home/checkout/topic/settings
  destination=$home/.config/tool/settings
  mkdir -p "$source" "$destination"
  printf 'tracked\n' >"$source/entry.md"
  printf 'hand written\n' >"$destination/entry.md"

  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'confirmed directory replaced'
  assert_contains "$home/stdout.log" 'Replaced settings as confirmed'
  assert_contains "$destination/entry.md" 'tracked'
  [[ ! -e $home/.config/tool/settings.backup ]] \
    || scenario_fail 'replace-confirmed left a backup of a directory'

  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$destination"
  assert_contains "$home/stdout.log" 'settings already linked'
  assert_not_contains "$home/stdout.log" 'Replaced settings as confirmed'

  rm "$destination"
  printf 'hand written\n' >"$destination"
  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'confirmed file replaced'
  [[ ! -e $home/.config/tool/settings.backup ]] \
    || scenario_fail 'replace-confirmed left a backup of a file'

  rm "$destination"
  ln -s "$home/elsewhere" "$destination"
  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'stale link replaced'

  rm "$destination"
  invoke_link "$home" --policy replace-confirmed --label 'settings' \
    "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'created when absent'
  assert_not_contains "$home/stdout.log" 'Replaced settings as confirmed'
}

# What an operator confirmed does not extend to the destinations whose removal
# is never what anyone meant: the home directory, a directory holding the
# source, and the filesystem root.
test_replace_confirmed_refuses_unsafe_destinations() {
  local home source

  home=$(scenario_tmpdir confirmed-guard)
  source=$home/checkout/topic/settings
  mkdir -p "$source"
  printf 'tracked\n' >"$source/entry.md"

  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-confirmed "$source" "$home"
  assert_contains "$home/stderr.log" 'refusing to remove'
  assert_contains "$home/stderr.log" 'under replace-confirmed'
  [[ -f $source/entry.md ]] || scenario_fail 'home refusal destroyed the source'

  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-confirmed "$source" "$home/checkout"
  assert_contains "$home/stderr.log" 'it contains the source'
  [[ -f $source/entry.md ]] || scenario_fail 'ancestor refusal destroyed the source'

  assert_fails_with_status 2 \
    invoke_link "$home" --policy replace-confirmed "$source" /
  assert_contains "$home/stderr.log" 'refusing to remove / under replace-confirmed'
  [[ -d /usr ]] || scenario_fail 'root refusal did not leave the filesystem intact'
}

# The classification a caller reads before it states an intent. link-dotfiles is
# its only consumer, and it had its own copy of this rule until the linker
# started answering the question it already had to answer to act.
test_status_classifies_without_changing_anything() {
  local home source destination

  home=$(scenario_tmpdir status)
  source=$home/source.conf
  destination=$home/.config/app/config
  mkdir -p "$(dirname "$destination")"
  printf 'tracked\n' >"$source"

  invoke_link "$home" --status "$source" "$destination"
  assert_equal 'absent' "$(cat "$home/stdout.log")" 'status for a free destination'

  printf 'local\n' >"$destination"
  invoke_link "$home" --status "$source" "$destination"
  assert_equal 'conflict' "$(cat "$home/stdout.log")" 'status for a real file'
  assert_contains "$destination" 'local'

  ln -sfn "$home/elsewhere.conf" "$destination"
  invoke_link "$home" --status "$source" "$destination"
  assert_equal 'conflict' "$(cat "$home/stdout.log")" 'status for a wrong link'

  ln -sfn "$source" "$destination"
  invoke_link "$home" --status "$source" "$destination"
  assert_equal 'current' "$(cat "$home/stdout.log")" 'status for the right link'

  # A relative link to the same file is the same link, which is the case the
  # two implementations used to answer differently.
  ln -sfn './source.conf' "$home/relative"
  invoke_link "$home" --status "$source" "$home/relative"
  assert_equal 'current' "$(cat "$home/stdout.log")" 'status for a relative link'

  assert_equal "$source" "$(readlink "$destination")" 'status left the link alone'
}

# Every caller created the directory before linking into it, so the linker owns
# that step. Asking for the status still changes nothing.
test_creates_a_missing_parent_directory() {
  local home source destination

  home=$(scenario_tmpdir parent)
  source=$home/source.conf
  destination=$home/.config/app/nested/config
  printf 'tracked\n' >"$source"

  invoke_link "$home" --status "$source" "$destination"
  assert_equal 'absent' "$(cat "$home/stdout.log")" 'status under a missing parent'
  [[ ! -e $home/.config ]] || scenario_fail 'status created the parent directory'

  invoke_link "$home" --label 'app config' "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'linked under a created parent'

  # A file where the directory belongs is not one to create, so the link
  # cannot be made.
  printf 'file\n' >"$home/blocked"
  assert_fails_with_status 1 invoke_link "$home" "$source" "$home/blocked/config"
  assert_contains "$home/stderr.log" 'cannot link config'
  assert_contains "$home/blocked" 'file'
}

test_status_refuses_a_missing_source() {
  local home

  home=$(scenario_tmpdir status-missing)
  if invoke_link "$home" --status "$home/missing" "$home/destination"; then
    return 1
  fi
  assert_contains "$home/stderr.log" 'source not found'
}

test_removes_an_owned_link_even_when_its_source_is_gone() {
  local home source destination

  home=$(scenario_tmpdir remove-owned)
  source=$home/checkout/topic/old.symlink
  destination=$home/.old
  mkdir -p "$home/checkout/topic"
  ln -s "$home/checkout" "$home/checkout-alias"
  ln -s './checkout-alias/topic/old.symlink' "$destination"

  invoke_link "$home" --remove-owned --label 'legacy config' "$source" "$destination"
  [[ ! -e $destination && ! -L $destination ]] || scenario_fail 'owned link was not removed'
  assert_contains "$home/stdout.log" 'Removed legacy config'
  assert_empty "$home/stderr.log"

  invoke_link "$home" --remove-owned "$source" "$destination"
  [[ ! -e $destination && ! -L $destination ]] || scenario_fail 'removal recreated the link'
  assert_empty "$home/stdout.log"
  assert_empty "$home/stderr.log"
}

test_removal_preserves_every_destination_it_does_not_own() {
  local home source destination

  home=$(scenario_tmpdir remove-conflicts)
  source=$home/source.conf
  printf 'tracked\n' >"$source"
  printf 'local\n' >"$home/local.conf"
  mkdir "$home/local-directory"
  printf 'keep\n' >"$home/local-directory/entry"
  ln -s './local.conf' "$home/other-link"
  ln -s './missing.conf' "$home/dangling-link"
  ln -s './missing-directory/../source.conf' "$home/unresolvable-link"

  for destination in "$source" "$home/local.conf" "$home/local-directory" \
    "$home/other-link" "$home/dangling-link" "$home/unresolvable-link" \
    "$home/absent-directory/config"; do
    invoke_link "$home" --remove-owned "$source" "$destination"
    assert_empty "$home/stdout.log"
    assert_empty "$home/stderr.log"
  done

  assert_contains "$source" 'tracked'
  assert_contains "$home/local.conf" 'local'
  assert_contains "$home/local-directory/entry" 'keep'
  assert_equal './local.conf' "$(readlink "$home/other-link")" 'foreign link preserved'
  assert_equal './missing.conf' "$(readlink "$home/dangling-link")" 'dangling conflict preserved'
  assert_equal './missing-directory/../source.conf' "$(readlink "$home/unresolvable-link")" \
    'unresolvable link preserved'
  [[ ! -e $home/absent-directory ]] || scenario_fail 'removal created a directory'
}

test_removal_leaves_the_source_and_existing_backup_untouched() {
  local home source destination

  home=$(scenario_tmpdir remove-existing)
  source=$home/source.conf
  destination=$home/.config
  printf 'tracked\n' >"$source"
  printf 'backup\n' >"$destination.backup"
  ln -s "$source" "$destination"

  invoke_link "$home" --remove-owned "$source" "$destination"
  [[ ! -e $destination && ! -L $destination ]] || scenario_fail 'owned link was not removed'
  assert_contains "$source" 'tracked'
  assert_contains "$destination.backup" 'backup'
}

test_status_cannot_be_combined_with_removal() {
  local home source destination

  home=$(scenario_tmpdir removal-mode)
  source=$home/source.conf
  destination=$home/.config
  printf 'tracked\n' >"$source"
  ln -s "$source" "$destination"

  assert_fails_with_status 2 invoke_link "$home" --status --remove-owned "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'status never removes a link'
  assert_fails_with_status 2 invoke_link "$home" --remove-owned --status "$source" "$destination"
  assert_equal "$source" "$(readlink "$destination")" 'reversed modes never remove a link'
}

test_missing_source_fails() {
  local home

  home=$(scenario_tmpdir missing)
  if invoke_link "$home" "$home/missing" "$home/destination"; then
    return 1
  fi
  assert_contains "$home/stderr.log" 'source not found'
}

scenario_run 'replace-with-backup links, backs up once, and stays idempotent' test_replace_with_backup_and_idempotent
scenario_run 'preserve-existing keeps local files' test_preserve_existing
scenario_run 'numbered-backup uses free backup suffixes' test_numbered_backup
scenario_run 'replace-confirmed destroys without a backup' \
  test_replace_confirmed_destroys_without_a_backup
scenario_run 'replace-confirmed refuses to remove unsafe destinations' \
  test_replace_confirmed_refuses_unsafe_destinations
scenario_run 'status classifies a destination without changing it' \
  test_status_classifies_without_changing_anything
scenario_run 'a missing parent directory is created, never by status' \
  test_creates_a_missing_parent_directory
scenario_run 'status refuses a missing source' test_status_refuses_a_missing_source
scenario_run 'missing source fails' test_missing_source_fails
scenario_run 'an owned link is removed even when its source is gone' \
  test_removes_an_owned_link_even_when_its_source_is_gone
scenario_run 'removal preserves every destination it does not own' \
  test_removal_preserves_every_destination_it_does_not_own
scenario_run 'removal leaves the source and existing backup untouched' \
  test_removal_leaves_the_source_and_existing_backup_untouched
scenario_run 'status cannot be combined with removal' \
  test_status_cannot_be_combined_with_removal
scenario_finish
