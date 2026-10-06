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
  cp "$REPOSITORY_ROOT/_scripts/installer-output.sh" "$repo/_scripts/installer-output.sh"
  cp "$REPOSITORY_ROOT/_scripts/topic-catalog" "$repo/_scripts/topic-catalog"
  chmod +x "$repo/_scripts/link-dotfiles" "$repo/_scripts/link-config" \
    "$repo/_scripts/topic-catalog"
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

# Each conflict takes the answer the person typed. The catalog loop used to
# share stdin with the prompt, so the answer was a character of the next
# catalog line: a typed "b" became the "o" of a path, the local file was
# removed without a backup, and the rest of that line was lost with its entry.
test_a_conflict_takes_the_typed_answer() {
  local repo

  repo=$(make_repo)
  printf 'existing\n' >"$repo/home/.bundle"
  printf 'keep\n' >"$repo/home/.config"
  printf 'bs' | invoke_linker "$repo"
  assert_contains "$repo/home/.bundle.backup" 'existing'
  assert_symlink "$repo/home/.bundle" 'the backed-up conflict is linked'
  assert_contains "$repo/home/.config" 'keep'
  [[ ! -L $repo/home/.config ]] \
    || scenario_fail 'a skipped conflict was replaced with a link'
  assert_count "$repo/stdout.log" 'File already exists' 2
}

test_an_all_answer_decides_the_later_conflicts() {
  local repo

  repo=$(make_repo)
  printf 'first\n' >"$repo/home/.bundle"
  printf 'second\n' >"$repo/home/.config"
  printf 'B' | invoke_linker "$repo"
  assert_contains "$repo/home/.bundle.backup" 'first'
  assert_contains "$repo/home/.config.backup" 'second'
  assert_count "$repo/stdout.log" 'File already exists' 1
}

# Without a terminal there is nobody to ask. Any default would decide a
# destination the person never chose about, so the run stops and says how to
# choose in advance.
test_a_conflict_without_an_answer_stops_the_run() {
  local repo

  repo=$(make_repo)
  printf 'keep\n' >"$repo/home/.config"
  assert_fails_with_status 1 invoke_linker "$repo" </dev/null
  assert_contains "$repo/home/.config" 'keep'
  [[ ! -L $repo/home/.config ]] \
    || scenario_fail 'an unanswered conflict was replaced with a link'
  assert_absent "$repo/home/.config.backup" 'an unanswered conflict was backed up'
  assert_contains "$repo/stderr.log" '--batch'
}

# The linker refuses to write over a backup it did not make. This module used
# to `mv` onto the same path unconditionally, so a second conflicting run
# destroyed whatever the first run had preserved.
test_an_existing_backup_stops_the_run() {
  local repo

  repo=$(make_repo)
  printf 'first\n' >"$repo/home/.config"
  invoke_linker "$repo" --batch backup
  assert_contains "$repo/home/.config.backup" 'first'

  # The single backup slot is taken, so the second run cannot link. It stops
  # rather than continuing: reporting success for a link that was never made
  # is what let an unlinked config reach setup's [ OK ].
  rm -f "$repo/home/.config"
  printf 'second\n' >"$repo/home/.config"
  assert_fails_with_status 1 invoke_linker "$repo" --batch backup
  assert_contains "$repo/home/.config.backup" 'first'
  assert_contains "$repo/home/.config" 'second'
  assert_contains "$repo/stderr.log" 'cannot link'
}

# overwrite destroys without a backup, so it inherits the linker's guard
# rather than running an unattended rm -rf on whatever it was handed. The
# catalog only ever yields $HOME/.<name> destinations, so the guard is unreachable
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
    "$repo/_scripts/link-config" --policy replace-confirmed \
    "$repo/sample/config.symlink" "$repo/home" || status=$?

  assert_equal 2 "$status" 'replace-confirmed refuses the home directory'
  assert_contains "$repo/stderr.log" 'refusing to remove'
  [[ -d $repo/home ]] || scenario_fail 'the home directory was removed'
}

# Every shell exports its active checkout's root, so a linker run from a
# worktree inherits one that names a different checkout. The links must still
# come from the checkout that contains the linker.
test_links_the_checkout_containing_the_linker() {
  local repo other

  repo=$(make_repo)
  other=$(make_repo)
  printf '%s\n' 'other checkout' >"$other/.localrc"
  scenario_capture "$repo" env \
    HOME="$repo/home" \
    DOTFILES_ROOT="$other" \
    "$repo/_scripts/link-dotfiles" --batch overwrite
  assert_equal "$repo/.localrc" "$(readlink "$repo/home/.localrc")" 'localrc link source'
  assert_equal "$repo/sample/config.symlink" "$(readlink "$repo/home/.config")" 'topic link source'
}

# Setup reads one topic catalog per run and hands the linker its link sources,
# so a linker given sources must not classify the checkout a second time. The
# classifier here fails if it runs at all.
refuse_classification() {
  scenario_write_executable "$1/_scripts/topic-catalog" <<'EOF'
#!/bin/sh
printf '%s\n' 'topic-catalog' >>"$SCENARIO_EVENT_LOG"
exit 1
EOF
}

test_links_exactly_the_sources_it_is_given() {
  local repo

  repo=$(make_repo)
  refuse_classification "$repo"
  invoke_linker "$repo" --batch overwrite -- "$repo/sample/config.symlink"
  assert_symlink "$repo/home/.localrc" 'localrc link'
  assert_symlink "$repo/home/.config" 'the given source is linked'
  assert_absent "$repo/home/.bundle" 'a source that was not given is not linked'
  assert_empty "$repo/events.log"
}

# A supplied topic catalog may hold no links. That must mean no links, not
# "classify the checkout instead", which would link what nobody listed.
test_an_empty_source_list_links_only_localrc() {
  local repo

  repo=$(make_repo)
  refuse_classification "$repo"
  invoke_linker "$repo" --batch overwrite --
  assert_symlink "$repo/home/.localrc" 'localrc link'
  assert_absent "$repo/home/.config" 'no topic link without a source'
  assert_absent "$repo/home/.bundle" 'no directory link without a source'
  assert_empty "$repo/events.log"
}

scenario_run 'batch overwrite links localrc and topic symlinks' test_batch_link_and_idempotent
scenario_run 'given sources are linked without classifying the checkout' \
  test_links_exactly_the_sources_it_is_given
scenario_run 'an empty source list links only localrc' \
  test_an_empty_source_list_links_only_localrc
scenario_run 'links come from the checkout containing the linker' \
  test_links_the_checkout_containing_the_linker
scenario_run 'batch backup and skip honor conflict policy' test_batch_backup_and_skip
scenario_run 'a conflict takes the typed answer, not the catalog' \
  test_a_conflict_takes_the_typed_answer
scenario_run 'an all-answer decides the later conflicts' \
  test_an_all_answer_decides_the_later_conflicts
scenario_run 'a conflict without an answer stops the run' \
  test_a_conflict_without_an_answer_stops_the_run
scenario_run 'an existing backup stops the run instead of reporting success' \
  test_an_existing_backup_stops_the_run
scenario_run 'every removal belongs to the config linker' \
  test_removal_belongs_to_the_linker
scenario_finish
