#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-test-runner-tests

# The runner discovers suites under a checkout root, so a fixture is a
# throwaway checkout holding stub suites and nothing else.
make_checkout() {
  local checkout
  checkout=$(scenario_tmpdir checkout)
  mkdir -p "$checkout/tests" "$checkout/_scripts"
  cp "$REPOSITORY_ROOT/_scripts/test" "$checkout/_scripts/test"
  chmod +x "$checkout/_scripts/test"
  printf '%s\n' "$checkout"
}

write_suite() {
  local checkout=$1
  local name=$2
  local status=$3

  scenario_write_executable "$checkout/tests/${name}_test.sh" <<EOF
#!/bin/sh
printf 'ok 1 - $name\n'
exit $status
EOF
}

invoke_runner() {
  local checkout=$1
  shift
  scenario_capture "$checkout" env \
    DOTFILES_TEST_ROOT="$checkout" \
    "$checkout/_scripts/test" "$@"
}

test_all_passing_suites_report_success() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 0
  write_suite "$checkout" beta 0

  invoke_runner "$checkout" \
    || scenario_fail 'runner failed while every suite passed'
  assert_contains "$checkout/stdout.log" '2 suite(s) passed'
}

# The defect this module exists to remove: a loop reports only the last
# suite's status, so a failure anywhere earlier disappears.
test_an_early_failure_fails_the_run() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 1
  write_suite "$checkout" beta 0
  write_suite "$checkout" gamma 0

  if invoke_runner "$checkout"; then
    scenario_fail 'runner reported success with a failing suite'
  fi
  assert_contains "$checkout/stderr.log" '1 of 3 suite(s) failed'
  assert_contains "$checkout/stderr.log" 'alpha'
}

test_every_failing_suite_is_named() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 1
  write_suite "$checkout" beta 0
  write_suite "$checkout" gamma 1

  if invoke_runner "$checkout"; then
    scenario_fail 'runner reported success with two failing suites'
  fi
  assert_contains "$checkout/stderr.log" '2 of 3 suite(s) failed'
  assert_contains "$checkout/stderr.log" 'alpha'
  assert_contains "$checkout/stderr.log" 'gamma'
  assert_not_contains "$checkout/stderr.log" 'beta'
}

test_pattern_selects_a_subset() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 0
  write_suite "$checkout" beta 1

  invoke_runner "$checkout" alpha \
    || scenario_fail 'filtered run failed on a passing suite'
  assert_contains "$checkout/stdout.log" '1 suite(s) passed'
  assert_not_contains "$checkout/stdout.log" 'beta'
}

test_unmatched_pattern_fails_rather_than_passing_vacuously() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 0

  if invoke_runner "$checkout" nosuchsuite; then
    scenario_fail 'an unmatched pattern reported success'
  fi
  assert_contains "$checkout/stderr.log" 'no suite matches'
}

test_checkout_root_suite_joins_the_run() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 0
  scenario_write_executable "$checkout/_scripts/test-checkout-root" <<'EOF'
#!/bin/sh
exit 1
EOF

  if invoke_runner "$checkout"; then
    scenario_fail 'runner ignored a failing test-checkout-root'
  fi
  assert_contains "$checkout/stderr.log" 'test-checkout-root'
}

test_invalid_usage_exits_two() {
  local checkout
  checkout=$(make_checkout)
  write_suite "$checkout" alpha 0

  assert_fails_with_status 2 \
    env DOTFILES_TEST_ROOT="$checkout" "$checkout/_scripts/test" --nope 2>/dev/null
  assert_fails_with_status 2 \
    env DOTFILES_TEST_ROOT="$checkout" "$checkout/_scripts/test" one two 2>/dev/null
}

scenario_run 'a run of passing suites succeeds' test_all_passing_suites_report_success
scenario_run 'a failure in the first suite fails the run' test_an_early_failure_fails_the_run
scenario_run 'every failing suite is named in the verdict' test_every_failing_suite_is_named
scenario_run 'a pattern selects a subset' test_pattern_selects_a_subset
scenario_run 'an unmatched pattern fails' test_unmatched_pattern_fails_rather_than_passing_vacuously
scenario_run 'test-checkout-root runs with the tests directory' test_checkout_root_suite_joins_the_run
scenario_run 'invalid usage exits 2' test_invalid_usage_exits_two
scenario_finish
