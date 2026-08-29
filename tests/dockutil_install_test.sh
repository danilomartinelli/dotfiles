#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-dockutil-install-tests

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/fake-bin" "$fixture/home/Downloads" "$fixture/home/Workspace"

  scenario_write_executable "$fixture/fake-bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Darwin
EOF

  scenario_write_executable "$fixture/fake-bin/dockutil" <<'EOF'
#!/bin/sh
printf 'dockutil %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  # The installer restarts the Dock; never let that reach the real machine.
  scenario_write_executable "$fixture/fake-bin/killall" <<'EOF'
#!/bin/sh
printf 'killall %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  printf '%s\n' "$fixture"
}

# Extra KEY=value arguments are passed through to env before the installer.
invoke_dockutil() {
  local fixture=$1
  local artifacts=$2
  shift 2

  scenario_capture "$artifacts" env \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    HOME="$fixture/home" \
    XDG_STATE_HOME="$fixture/state" \
    WORKSPACE="$fixture/home/Workspace" \
    "$@" \
    "$REPOSITORY_ROOT/dockutil/install.sh"
}

test_first_run_rebuilds_the_dock_and_records_the_marker() {
  local fixture
  fixture=$(make_fixture)
  invoke_dockutil "$fixture" "$fixture/run1"

  assert_contains "$fixture/run1/events.log" 'dockutil --remove all'
  assert_contains "$fixture/run1/stdout.log" '✓ dock configured'
  [[ -f $fixture/state/dotfiles/dock-applied ]] \
    || scenario_fail 'run-once marker not recorded'
}

test_second_run_leaves_a_manual_dock_alone() {
  local fixture
  fixture=$(make_fixture)
  invoke_dockutil "$fixture" "$fixture/run1"
  invoke_dockutil "$fixture" "$fixture/run2"

  # Rebuilding wipes the Dock, so an update run must not touch it at all.
  assert_not_contains "$fixture/run2/events.log" 'dockutil'
  assert_contains "$fixture/run2/stdout.log" \
    'dock layout already applied; run DOTFILES_RESET=dock dot to reapply'
  assert_contains "$fixture/run2/stdout.log" '✓ dock configured'
}

test_reset_re_arms_the_dock_rebuild() {
  local fixture
  fixture=$(make_fixture)
  invoke_dockutil "$fixture" "$fixture/run1"
  invoke_dockutil "$fixture" "$fixture/run2" DOTFILES_RESET=dock

  assert_contains "$fixture/run2/events.log" 'dockutil --remove all'
}

scenario_run 'the first run rebuilds the Dock and records its marker' \
  test_first_run_rebuilds_the_dock_and_records_the_marker
scenario_run 'a second run leaves a manually arranged Dock alone' \
  test_second_run_leaves_a_manual_dock_alone
scenario_run 'DOTFILES_RESET=dock re-arms the rebuild' \
  test_reset_re_arms_the_dock_rebuild
scenario_finish
