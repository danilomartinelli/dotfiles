#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-generated-file-tests

MODULE=$REPOSITORY_ROOT/_scripts/generated-file.sh

# Run a renderer-shaped consumer against the module. Both real callers set a
# mode, sync one or more files, then end on the verdict, so the fixture runs the
# same three steps rather than reaching for the functions one at a time.
# Sets SCENARIO_STATUS to the consumer's exit status, the way every suite here
# spells `|| status=$?` around scenario_capture.
invoke_module() {
  local fixture=$1
  local body=$2

  cat >"$fixture/consumer.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
. "$MODULE"
$body
EOF
  chmod +x "$fixture/consumer.sh"
  SCENARIO_STATUS=0
  scenario_capture "$fixture" "$fixture/consumer.sh" || SCENARIO_STATUS=$?
}

test_an_unchanged_file_is_silent_and_unwritten() {
  local fixture
  fixture=$(scenario_tmpdir unchanged)

  printf 'same\n' >"$fixture/rendered"
  printf 'same\n' >"$fixture/stored"

  invoke_module "$fixture" "
generated_file_mode write
generated_file_sync '$fixture/rendered' '$fixture/stored' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 0 "$SCENARIO_STATUS" 'unchanged file status'
  assert_not_contains "$fixture/stdout.log" 'rendered'
  assert_equal 'same' "$(cat "$fixture/stored")" 'stored file untouched'
}

test_a_changed_file_is_written_and_named() {
  local fixture
  fixture=$(scenario_tmpdir changed)

  printf 'new\n' >"$fixture/rendered"
  printf 'old\n' >"$fixture/stored"

  invoke_module "$fixture" "
generated_file_mode write
generated_file_sync '$fixture/rendered' '$fixture/stored' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 0 "$SCENARIO_STATUS" 'write status'
  assert_contains "$fixture/stdout.log" 'rendered stored'
  assert_equal 'new' "$(cat "$fixture/stored")" 'stored file rewritten'
}

test_a_missing_stored_file_is_created_with_its_directory() {
  local fixture
  fixture=$(scenario_tmpdir created)

  printf 'fresh\n' >"$fixture/rendered"

  invoke_module "$fixture" "
generated_file_mode write
generated_file_sync '$fixture/rendered' '$fixture/nested/deep/stored' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 0 "$SCENARIO_STATUS" 'created status'
  assert_equal 'fresh' "$(cat "$fixture/nested/deep/stored")" 'nested file written'
}

# The write path used to be unreachable from any suite: both renderers are only
# ever run with --check against tracked files that are already current.
test_check_reports_without_writing_and_fails_the_verdict() {
  local fixture
  fixture=$(scenario_tmpdir check)

  printf 'new\n' >"$fixture/rendered"
  printf 'old\n' >"$fixture/stored"

  invoke_module "$fixture" "
generated_file_mode check
generated_file_sync '$fixture/rendered' '$fixture/stored' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 1 "$SCENARIO_STATUS" 'check verdict status'
  assert_contains "$fixture/stderr.log" 'stale: stored'
  assert_contains "$fixture/stderr.log" '-old'
  assert_contains "$fixture/stderr.log" '+new'
  assert_contains "$fixture/stderr.log" 'payload is out of date (1 file(s)); run render'
  assert_equal 'old' "$(cat "$fixture/stored")" 'stored file untouched under check'
}

# A payload that was never rendered has no stored half, and `diff` would report
# that on the same stream as the difference a person is reading.
test_check_names_a_never_rendered_payload_without_a_diff_error() {
  local fixture
  fixture=$(scenario_tmpdir absent)

  printf 'fresh\n' >"$fixture/rendered"

  invoke_module "$fixture" "
generated_file_mode check
generated_file_sync '$fixture/rendered' '$fixture/absent-payload' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 1 "$SCENARIO_STATUS" 'absent payload status'
  assert_contains "$fixture/stderr.log" 'stale: absent-payload'
  assert_not_contains "$fixture/stderr.log" 'No such file'
}

# The whole reason the third argument is a root: two callers computing a display
# string against two different roots both produced "README.md".
test_two_payloads_under_one_root_report_distinguishable_paths() {
  local fixture
  fixture=$(scenario_tmpdir roots)

  mkdir -p "$fixture/opencode"
  printf 'new\n' >"$fixture/rendered"
  printf 'old\n' >"$fixture/README.md"
  printf 'old\n' >"$fixture/opencode/README.md"

  invoke_module "$fixture" "
generated_file_mode check
generated_file_sync '$fixture/rendered' '$fixture/README.md' '$fixture'
generated_file_sync '$fixture/rendered' '$fixture/opencode/README.md' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 1 "$SCENARIO_STATUS" 'two stale payloads status'
  assert_contains "$fixture/stderr.log" 'stale: README.md'
  assert_contains "$fixture/stderr.log" 'stale: opencode/README.md'
  assert_contains "$fixture/stderr.log" 'payload is out of date (2 file(s)); run render'
}

# A fixture tree is not under the checkout, and a path it cannot shorten is
# reported whole rather than mangled.
test_a_payload_outside_the_root_is_reported_whole() {
  local fixture
  fixture=$(scenario_tmpdir outside)

  printf 'new\n' >"$fixture/rendered"
  printf 'old\n' >"$fixture/stored"

  invoke_module "$fixture" "
generated_file_mode check
generated_file_sync '$fixture/rendered' '$fixture/stored' '/nowhere'
generated_file_verdict 'payload is' render
"

  assert_equal 1 "$SCENARIO_STATUS" 'outside-root status'
  assert_contains "$fixture/stderr.log" "stale: $fixture/stored"
}

test_a_clean_check_run_reports_up_to_date() {
  local fixture
  fixture=$(scenario_tmpdir clean)

  printf 'same\n' >"$fixture/rendered"
  printf 'same\n' >"$fixture/stored"

  invoke_module "$fixture" "
generated_file_mode check
generated_file_sync '$fixture/rendered' '$fixture/stored' '$fixture'
generated_file_verdict 'payload is' render
"

  assert_equal 0 "$SCENARIO_STATUS" 'clean check status'
  assert_contains "$fixture/stdout.log" 'payload is up to date.'
}

scenario_run 'an unchanged file is silent and unwritten' \
  test_an_unchanged_file_is_silent_and_unwritten
scenario_run 'a changed file is written and named' \
  test_a_changed_file_is_written_and_named
scenario_run 'a missing stored file is created with its directory' \
  test_a_missing_stored_file_is_created_with_its_directory
scenario_run 'check reports without writing and fails the verdict' \
  test_check_reports_without_writing_and_fails_the_verdict
scenario_run 'check names a never-rendered payload without a diff error' \
  test_check_names_a_never_rendered_payload_without_a_diff_error
scenario_run 'two payloads under one root report distinguishable paths' \
  test_two_payloads_under_one_root_report_distinguishable_paths
scenario_run 'a payload outside the root is reported whole' \
  test_a_payload_outside_the_root_is_reported_whole
scenario_run 'a clean check run reports up to date' \
  test_a_clean_check_run_reports_up_to_date

scenario_finish
