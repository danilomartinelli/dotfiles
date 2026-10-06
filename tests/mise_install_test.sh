#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/fixture.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/fixture.sh"
scenario_init dotfiles-mise-install-tests

new_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/repository/mise"
  cp -R "$REPOSITORY_ROOT/_scripts" "$fixture/repository/_scripts"
  for source in install.sh _configure-trust.sh _extras.py config.toml mise.lock; do
    cp "$REPOSITORY_ROOT/mise/$source" "$fixture/repository/mise/$source"
  done
  stub_mise "$fixture/fake-bin"
  printf '%s\n' "$fixture"
}

invoke_mise() {
  local fixture=$1
  shift
  fixture_run "$fixture" "FAKE_MISE_TRACE=$fixture/mise-trace.jsonl" "$@" -- "$fixture/repository/mise/install.sh"
}

# A plain install rewrites the lock into a shape `mise lock` does not produce,
# so every `dot` left the tree dirty. The run installs what the lock records
# and has no other way to install anything.
test_the_run_installs_what_the_lock_records() {
  local fixture
  fixture=$(new_fixture)

  invoke_mise "$fixture"

  assert_contains "$fixture/events.log" 'mise install'
  assert_count "$fixture/events.log" 'mise install' 1
  assert_contains "$fixture/stdout.log" 'Mise runtimes installed successfully'
}

# A declaration changed without its lock is the failure this run now surfaces,
# so the error names the one command that settles the lock, and nothing after
# the install runs against tools the lock did not describe.
test_a_lock_behind_its_declarations_names_the_refresh() {
  local fixture status=0
  fixture=$(new_fixture)

  invoke_mise "$fixture" FAIL_MISE_INSTALL=1 || status=$?

  assert_equal 1 "$status" 'failed install status'
  assert_contains "$fixture/stderr.log" 'Failed to install Mise runtimes'
  assert_contains "$fixture/stderr.log" "mise-policy <checkout> lock <tool>"
  assert_not_contains "$fixture/events.log" 'mise prune'
}

# Pruning rewrites the lock in the install shape just as a plain install
# does, so the run that never writes the lock turns lockfile writes off for it.
test_pruning_leaves_the_lock_alone() {
  local fixture
  fixture=$(new_fixture)

  invoke_mise "$fixture"

  assert_contains "$fixture/events.log" 'mise prune --yes'
  cmp "$fixture/repository/mise/mise.lock" "$REPOSITORY_ROOT/mise/mise.lock"
  assert_not_contains "$fixture/events.log" 'mise trust'
  assert_not_contains "$fixture/mise-trace.jsonl" '"locked": false'
}

# The postinstall repairs look their tool up with `mise where`, which fails for a
# tool that is not installed. Under `set -e` that substitution used to end the
# run on the spot, silently and with a failing status, so a machine without
# Claude Code could never reach the OpenCode repair or finish the topic.
test_an_absent_agent_cli_does_not_stop_the_run() {
  local fixture status=0
  fixture=$(new_fixture)

  invoke_mise "$fixture" || status=$?

  assert_equal 0 "$status" 'run status without the agent CLIs'
  assert_contains "$fixture/events.log" 'mise where npm:@anthropic-ai/claude-code'
  assert_contains "$fixture/events.log" 'mise where npm:opencode-ai'
  assert_not_contains "$fixture/stdout.log" 'claude-code postinstall'
  assert_not_contains "$fixture/stdout.log" 'opencode native binary'
}

scenario_run 'the run installs what the lock records' \
  test_the_run_installs_what_the_lock_records
scenario_run 'a lock behind its declarations names the refresh' \
  test_a_lock_behind_its_declarations_names_the_refresh
scenario_run 'pruning leaves the lock alone' test_pruning_leaves_the_lock_alone
scenario_run 'an absent agent CLI does not stop the run' \
  test_an_absent_agent_cli_does_not_stop_the_run

test_formatter_reconciliation_failure_stops_before_pruning() {
  local fixture status=0
  fixture=$(new_fixture)
  invoke_mise "$fixture" FAKE_MISE_MDFORMAT_HOME="$fixture/formatter" \
    FAIL_MISE_EXEC=1 || status=$?
  assert_equal 1 "$status" 'formatter mismatch status'
  assert_contains "$fixture/events.log" 'mise exec python -- python3'
  assert_contains "$fixture/stderr.log" 'Failed to reconcile Mise formatter plugins'
  assert_not_contains "$fixture/events.log" 'mise prune'
}

scenario_run 'formatter reconciliation failure stops before pruning' \
  test_formatter_reconciliation_failure_stops_before_pruning

scenario_finish
