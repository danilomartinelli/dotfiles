#!/usr/bin/env bash
#
# The cache for completions a CLI generates about itself.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-generated-completion-tests

# Create a fixture whose fake `tool` prints one completion line and records
# each time it is asked to.
new_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/home" "$fixture/bin"
  scenario_write_executable "$fixture/bin/tool" <<'TOOL'
#!/bin/sh
[ "${FAIL_TOOL:-0}" = 0 ] || exit "$FAIL_TOOL"
printf '%s\n' generated >>"$SCENARIO_EVENT_LOG"
printf 'typeset -g TOOL_COMPLETION=%s\n' "${FAKE_TOOL_VERSION:-1}"
TOOL
  printf '%s\n' "$fixture"
}

# Ask a fresh shell for the tool's completion and print what sourcing it set.
# Usage: load_completion <fixture> [KEY=value ...]
load_completion() {
  local fixture=$1
  shift

  # shellcheck disable=SC2016 # The child Zsh expands these.
  env -i HOME="$fixture/home" PATH="$fixture/bin:/usr/bin:/bin" \
    SCENARIO_EVENT_LOG="$fixture/events.log" MODULE="$REPOSITORY_ROOT/zsh/_generated-completion.zsh" \
    "$@" zsh -d -f -c '
      source "$MODULE"
      if _dotfiles_generated_completion tool completion zsh; then
        source "$REPLY"
      fi
      print -r -- "${TOOL_COMPLETION-none}"
    '
}

test_a_second_shell_reuses_the_generated_completion() {
  local fixture
  fixture=$(new_fixture)

  assert_equal 1 "$(load_completion "$fixture")" 'first shell'
  assert_equal 1 "$(load_completion "$fixture")" 'second shell'
  assert_count "$fixture/events.log" generated 1
}

test_a_changed_command_regenerates_its_completion() {
  local fixture
  fixture=$(new_fixture)

  load_completion "$fixture" >/dev/null
  touch -t 203001010000 "$fixture/bin/tool"

  assert_equal 2 "$(load_completion "$fixture" FAKE_TOOL_VERSION=2)" 'after the change'
  assert_count "$fixture/events.log" generated 2
}

test_a_failed_generation_leaves_no_cache_behind() {
  local fixture
  fixture=$(new_fixture)

  assert_equal none "$(load_completion "$fixture" FAIL_TOOL=3)" 'failed generation'
  assert_equal 1 "$(load_completion "$fixture")" 'next shell'
}

test_a_missing_command_is_skipped() {
  local fixture
  fixture=$(new_fixture)
  rm "$fixture/bin/tool"

  assert_equal none "$(load_completion "$fixture")" 'missing command'
}

scenario_run 'a second shell reuses the generated completion' \
  test_a_second_shell_reuses_the_generated_completion
scenario_run 'a changed command regenerates its completion' \
  test_a_changed_command_regenerates_its_completion
scenario_run 'a failed generation leaves no cache behind' \
  test_a_failed_generation_leaves_no_cache_behind
scenario_run 'a missing command is skipped' \
  test_a_missing_command_is_skipped

scenario_finish
