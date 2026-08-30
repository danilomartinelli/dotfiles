#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-dock-install-tests

# A synthetic layout, so adding an app to the real Dock never breaks this file.
# Rows are written with $HOME and $WORKSPACE rather than fixture paths, which
# makes the expansion part of every scenario instead of a separate concern.
write_catalog() {
  scenario_write_file "$1" <<'EOF'
# test layout
apps	$HOME/Applications/One.app	-	-
apps	$HOME/Applications/Two.app	-	-
others	$WORKSPACE	list	folder
others	$HOME/Downloads	list	folder
EOF
}

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p \
    "$fixture/fake-bin" \
    "$fixture/home/Applications/One.app" \
    "$fixture/home/Applications/Two.app" \
    "$fixture/home/Downloads" \
    "$fixture/home/Workspace"

  write_catalog "$fixture/layout.tsv"

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
invoke_dock() {
  local fixture=$1
  local artifacts=$2
  shift 2

  scenario_capture "$artifacts" env \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    HOME="$fixture/home" \
    XDG_STATE_HOME="$fixture/state" \
    WORKSPACE="$fixture/home/Workspace" \
    DOTFILES_DOCK_CATALOG="$fixture/layout.tsv" \
    "$@" \
    "$REPOSITORY_ROOT/dock/install.sh"
}

test_first_run_rebuilds_the_dock_and_records_the_marker() {
  local fixture
  fixture=$(make_fixture)
  invoke_dock "$fixture" "$fixture/run1"

  assert_contains "$fixture/run1/events.log" 'dockutil --remove all'
  assert_contains "$fixture/run1/stdout.log" '✓ dock configured'
  [[ -f $fixture/state/dotfiles/dock-applied ]] \
    || scenario_fail 'run-once marker not recorded'
}

test_second_run_leaves_a_manual_dock_alone() {
  local fixture
  fixture=$(make_fixture)
  invoke_dock "$fixture" "$fixture/run1"
  invoke_dock "$fixture" "$fixture/run2"

  # Rebuilding wipes the Dock, so an update run must not touch it at all.
  assert_not_contains "$fixture/run2/events.log" 'dockutil'
  assert_contains "$fixture/run2/stdout.log" \
    'dock layout already applied; run DOTFILES_RESET=dock dot to reapply'
  assert_contains "$fixture/run2/stdout.log" '✓ dock configured'
}

test_reset_re_arms_the_dock_rebuild() {
  local fixture
  fixture=$(make_fixture)
  invoke_dock "$fixture" "$fixture/run1"
  invoke_dock "$fixture" "$fixture/run2" DOTFILES_RESET=dock

  assert_contains "$fixture/run2/events.log" 'dockutil --remove all'
}

test_catalog_order_and_expansion() {
  local fixture
  local events
  fixture=$(make_fixture)
  invoke_dock "$fixture" "$fixture/run1"
  events=$fixture/run1/events.log

  # The wipe precedes every add, apps keep row order, folders follow the apps,
  # and the last others row lands closest to the trash.
  assert_before "$events" 'dockutil --remove all' \
    "dockutil --add $fixture/home/Applications/One.app --section apps"
  assert_before "$events" \
    "dockutil --add $fixture/home/Applications/One.app --section apps" \
    "dockutil --add $fixture/home/Applications/Two.app --section apps"
  assert_before "$events" \
    "dockutil --add $fixture/home/Applications/Two.app --section apps" \
    "dockutil --add $fixture/home/Workspace --section others"
  assert_before "$events" \
    "dockutil --add $fixture/home/Workspace --section others" \
    "dockutil --add $fixture/home/Downloads --section others"

  # Folder rows carry their view and display; app rows carry neither.
  assert_contains "$events" \
    "dockutil --add $fixture/home/Downloads --section others --view list --display folder --no-restart"
  assert_contains "$events" \
    "dockutil --add $fixture/home/Applications/One.app --section apps --no-restart"
  assert_contains "$events" 'killall Dock'
}

test_missing_entry_is_skipped_and_the_rest_still_applies() {
  local fixture
  fixture=$(make_fixture)
  rm -rf "$fixture/home/Applications/Two.app"
  invoke_dock "$fixture" "$fixture/run1"

  assert_contains "$fixture/run1/stderr.log" \
    "Warning: Skipping Two (not found at $fixture/home/Applications/Two.app)"
  assert_not_contains "$fixture/run1/events.log" 'Two.app'
  assert_contains "$fixture/run1/events.log" \
    "dockutil --add $fixture/home/Downloads --section others"
  # The marker is still recorded, so a skipped entry stays missing until a
  # reset. Pinned deliberately: this is what hid a wrong path for months.
  [[ -f $fixture/state/dotfiles/dock-applied ]] \
    || scenario_fail 'run-once marker not recorded after a skipped entry'
}

# shellcheck disable=SC2016  # rows keep $HOME literal; the applier expands it
test_invalid_rows_fail_the_apply() {
  local fixture

  fixture=$(make_fixture)
  printf 'sidebar\t$HOME/Downloads\t-\t-\n' >"$fixture/layout.tsv"
  if invoke_dock "$fixture" "$fixture/run1"; then
    return 1
  fi
  assert_contains "$fixture/run1/stderr.log" "unknown catalog section 'sidebar'"

  fixture=$(make_fixture)
  printf 'others\t$HOME/Downloads\tcarousel\tfolder\n' >"$fixture/layout.tsv"
  if invoke_dock "$fixture" "$fixture/run2"; then
    return 1
  fi
  assert_contains "$fixture/run2/stderr.log" "unknown catalog view 'carousel'"

  fixture=$(make_fixture)
  printf 'others\t$HOME/Downloads\tlist\tdrawer\n' >"$fixture/layout.tsv"
  if invoke_dock "$fixture" "$fixture/run3"; then
    return 1
  fi
  assert_contains "$fixture/run3/stderr.log" "unknown catalog display 'drawer'"

  fixture=$(make_fixture)
  printf 'others\t$HOME/Downloads\n' >"$fixture/layout.tsv"
  if invoke_dock "$fixture" "$fixture/run4"; then
    return 1
  fi
  assert_contains "$fixture/run4/stderr.log" 'invalid catalog row'
}

test_missing_catalog_fails_the_apply() {
  local fixture
  fixture=$(make_fixture)
  rm -f "$fixture/layout.tsv"

  if invoke_dock "$fixture" "$fixture/run1"; then
    return 1
  fi
  assert_contains "$fixture/run1/stderr.log" 'Dock layout catalog not found'
  assert_not_contains "$fixture/run1/events.log" 'dockutil --remove all'
}

scenario_run 'the first run rebuilds the Dock and records its marker' \
  test_first_run_rebuilds_the_dock_and_records_the_marker
scenario_run 'a second run leaves a manually arranged Dock alone' \
  test_second_run_leaves_a_manual_dock_alone
scenario_run 'DOTFILES_RESET=dock re-arms the rebuild' \
  test_reset_re_arms_the_dock_rebuild
scenario_run 'the catalog decides order, section, and path expansion' \
  test_catalog_order_and_expansion
scenario_run 'a missing entry is skipped and the remaining rows still apply' \
  test_missing_entry_is_skipped_and_the_rest_still_applies
scenario_run 'invalid catalog rows fail the apply' test_invalid_rows_fail_the_apply
scenario_run 'a missing catalog fails the apply' test_missing_catalog_fails_the_apply
scenario_finish
