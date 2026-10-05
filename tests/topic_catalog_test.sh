#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
CATALOG=$REPOSITORY_ROOT/_scripts/topic-catalog
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-topic-catalog-tests

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir catalog-fixture)

  mkdir -p \
    "$fixture/.hidden" \
    "$fixture/_private" \
    "$fixture/_scripts" \
    "$fixture/alpha/bundle.symlink" \
    "$fixture/alpha/_private/nested" \
    "$fixture/alpha/.dot" \
    "$fixture/alpha/nested" \
    "$fixture/bin" \
    "$fixture/docs/agents" \
    "$fixture/empty" \
    "$fixture/functions" \
    "$fixture/homebrew" \
    "$fixture/spaced topic" \
    "$fixture/tests" \
    "$fixture/zsh"

  scenario_write_file "$fixture/dotfiles-root.symlink" <<'EOF'
resolver
EOF
  scenario_write_file "$fixture/.hidden/secret.zsh" <<'EOF'
hidden
EOF
  scenario_write_file "$fixture/_private/ignored.zsh" <<'EOF'
private
EOF
  scenario_write_file "$fixture/_private/install.sh" <<'EOF'
private
EOF
  scenario_write_file "$fixture/_private/private.symlink" <<'EOF'
private
EOF
  scenario_write_file "$fixture/_scripts/installer-preamble.sh" <<'EOF'
preamble
EOF
  scenario_write_file "$fixture/alpha/alpha.symlink" <<'EOF'
link
EOF
  scenario_write_file "$fixture/alpha/bundle.symlink/config.json" <<'EOF'
directory link
EOF
  scenario_write_file "$fixture/alpha/bundle.symlink/internal.zsh" <<'EOF'
application-owned shell file
EOF
  scenario_write_file "$fixture/alpha/_draft.symlink" <<'EOF'
private
EOF
  scenario_write_file "$fixture/alpha/install.sh" <<'EOF'
installer
EOF
  scenario_write_file "$fixture/alpha/path.zsh" <<'EOF'
path
EOF
  scenario_write_file "$fixture/alpha/aliases.zsh" <<'EOF'
aliases
EOF
  scenario_write_file "$fixture/alpha/completion.zsh" <<'EOF'
completion
EOF
  scenario_write_file "$fixture/alpha/prompt.zsh" <<'EOF'
main
EOF
  scenario_write_file "$fixture/alpha/topic.zsh" <<'EOF'
main
EOF
  scenario_write_file "$fixture/alpha/_hidden.zsh" <<'EOF'
private
EOF
  scenario_write_file "$fixture/alpha/_private/nested/deep.zsh" <<'EOF'
private
EOF
  scenario_write_file "$fixture/alpha/.dot/hidden.zsh" <<'EOF'
private
EOF
  scenario_write_file "$fixture/alpha/nested/deep.zsh" <<'EOF'
main
EOF
  scenario_write_file "$fixture/bin/tool.zsh" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/bin/install.sh" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/bin/bin.symlink" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/docs/notes.zsh" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/docs/install.sh" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/docs/docs.symlink" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/docs/agents/issue-tracker.md" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/functions/helper.zsh" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/homebrew/install.sh" <<'EOF'
reserved phase
EOF
  scenario_write_file "$fixture/spaced topic/spaced file.zsh" <<'EOF'
main
EOF
  scenario_write_file "$fixture/tests/suite.zsh" <<'EOF'
reserved
EOF
  scenario_write_file "$fixture/zsh/prompt.zsh" <<'EOF'
prompt
EOF

  printf '%s\n' "$fixture"
}

golden_manifest() {
  local fixture=$1

  printf '%s\t%s\n' aliases "$fixture/alpha/aliases.zsh"
  printf '%s\t%s\n' completion "$fixture/alpha/completion.zsh"
  printf '%s\t%s\n' installer "$fixture/alpha/install.sh"
  printf '%s\t%s\n' link "$fixture/alpha/alpha.symlink"
  printf '%s\t%s\n' link "$fixture/alpha/bundle.symlink"
  printf '%s\t%s\n' link "$fixture/dotfiles-root.symlink"
  printf '%s\t%s\n' main "$fixture/alpha/aliases.zsh"
  printf '%s\t%s\n' main "$fixture/alpha/nested/deep.zsh"
  printf '%s\t%s\n' main "$fixture/alpha/prompt.zsh"
  printf '%s\t%s\n' main "$fixture/alpha/topic.zsh"
  printf '%s\t%s\n' main "$fixture/spaced topic/spaced file.zsh"
  printf '%s\t%s\n' path "$fixture/alpha/path.zsh"
  printf '%s\t%s\n' prompt "$fixture/zsh/prompt.zsh"
  printf '%s\t%s\n' topic "$fixture/alpha"
  printf '%s\t%s\n' topic "$fixture/empty"
  printf '%s\t%s\n' topic "$fixture/homebrew"
  printf '%s\t%s\n' topic "$fixture/spaced topic"
  printf '%s\t%s\n' topic "$fixture/zsh"
}

test_golden_manifest() {
  local fixture
  local expected
  local actual

  fixture=$(make_fixture)
  expected=$fixture/expected.manifest
  actual=$fixture/actual.manifest

  golden_manifest "$fixture" >"$expected"
  "$CATALOG" "$fixture" >"$actual" || return 1

  if ! diff -u "$expected" "$actual"; then
    scenario_fail 'catalog output differs from the golden manifest'
  fi
}

# Zsh startup runs the classifier on every shell, so its cost must not grow
# with the number of topics. On a PATH holding only Bash and logging spies for
# find and sort, any other command is missing and fails the run, and a find per
# topic shows up in the log. The fixture has several topics with .zsh files.
test_process_count_is_independent_of_topic_count() {
  local fixture
  local run
  local spies
  local spied
  local real

  fixture=$(make_fixture)
  run=$(scenario_tmpdir spied-run)
  spies=$run/bin
  mkdir -p "$spies"
  ln -s "$(command -v bash)" "$spies/bash"
  for spied in find sort; do
    real=$(command -v "$spied")
    scenario_write_executable "$spies/$spied" <<EOF
#!/bin/sh
printf '%s\n' $spied >>"\$SCENARIO_EVENT_LOG"
exec $real "\$@"
EOF
  done

  "$CATALOG" "$fixture" >"$run/expected.manifest" || return 1
  scenario_capture "$run/capture" env PATH="$spies" "$CATALOG" "$fixture" \
    || scenario_fail "catalog needed a command other than find and sort: $(cat "$run/capture/stderr.log")"
  diff -u "$run/expected.manifest" "$run/capture/stdout.log" \
    || scenario_fail 'catalog output changed under the restricted PATH'
  assert_count "$run/capture/events.log" find 1
  assert_count "$run/capture/events.log" sort 1
}

test_relative_root_resolves_to_absolute_records() {
  local fixture
  local parent
  local output

  fixture=$(make_fixture)
  parent=$(dirname -- "$fixture")

  output=$(
    cd "$parent" || exit 1
    "$CATALOG" "./$(basename -- "$fixture")"
  ) || return 1

  if printf '%s\n' "$output" | grep -Fqv "$fixture/"; then
    scenario_fail 'catalog did not emit absolute paths'
    return 1
  fi
  return 0
}

test_invalid_usage() {
  local fixture

  fixture=$(make_fixture)

  assert_fails_with_status 2 "$CATALOG"
  assert_fails_with_status 2 "$CATALOG" "$fixture" extra
  assert_fails_with_output 'usage message' 'Usage: _scripts/topic-catalog' "$CATALOG"
}

test_invalid_root() {
  local fixture
  local regular_file

  fixture=$(make_fixture)
  regular_file=$fixture/alpha/topic.zsh

  assert_fails_with_status 1 "$CATALOG" "$fixture/missing"
  assert_fails_with_status 1 "$CATALOG" "$regular_file"
  assert_fails_with_output 'missing root error' 'invalid repository root' \
    "$CATALOG" "$fixture/missing"
}

scenario_run 'catalog matches the golden manifest' test_golden_manifest
scenario_run 'catalog starts one find and one sort whatever the topic count' \
  test_process_count_is_independent_of_topic_count
scenario_run 'relative roots resolve to absolute records' test_relative_root_resolves_to_absolute_records
scenario_run 'invalid usage exits with status 2' test_invalid_usage
scenario_run 'invalid roots exit with status 1' test_invalid_root
scenario_finish
