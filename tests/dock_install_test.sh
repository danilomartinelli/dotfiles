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
  fixture=$(installer_fixture)
  mkdir -p \
    "$fixture/home/Applications/One.app" \
    "$fixture/home/Applications/Two.app" \
    "$fixture/home/Downloads" \
    "$fixture/home/Workspace"

  write_catalog "$fixture/layout.tsv"

  scenario_write_executable "$fixture/fake-bin/dockutil" <<'EOF'
#!/bin/sh
printf 'dockutil %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  # The installer restarts the Dock; never let that reach the real machine.
  stub_killall "$fixture/fake-bin"

  printf '%s\n' "$fixture"
}

# Extra KEY=value arguments are passed through to env before the installer.
invoke_dock() {
  local fixture=$1
  local artifacts=$2
  shift 2

  fixture_run "$fixture" --artifacts "$artifacts" \
    WORKSPACE="$fixture/home/Workspace" \
    DOTFILES_DOCK_CATALOG="$fixture/layout.tsv" \
    "$@" \
    -- "$REPOSITORY_ROOT/dock/install.sh"
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

# Every fault in the layout is reported in one run, by line, and none of them
# reaches the Dock: the check runs before the wipe, so a typo in the last row
# cannot leave the Dock cleared and never restarted.
# shellcheck disable=SC2016  # rows keep $HOME literal; the applier expands it
test_an_invalid_layout_leaves_the_dock_untouched() {
  local fixture
  local stderr

  fixture=$(make_fixture)
  scenario_write_file "$fixture/layout.tsv" <<'EOF'
apps	$HOME/Applications/One.app	-	-
sidebar	$HOME/Applications/Two.app	-	-
others	$WORKSPACE	carousel	folder
others	$HOME/Downloads	list	drawer
others	$HOEM/Desktop
apps	$HOME/Applications/One.app	-	-
EOF
  if invoke_dock "$fixture" "$fixture/run1"; then
    return 1
  fi
  stderr=$fixture/run1/stderr.log

  assert_contains "$stderr" "$fixture/layout.tsv:2: unknown section 'sidebar'"
  assert_contains "$stderr" "$fixture/layout.tsv:3: unknown view 'carousel'"
  assert_contains "$stderr" "$fixture/layout.tsv:4: unknown display 'drawer'"
  assert_contains "$stderr" "$fixture/layout.tsv:5: unknown placeholder \$HOEM"
  assert_contains "$stderr" "$fixture/layout.tsv:5: missing view"
  assert_contains "$stderr" "$fixture/layout.tsv:5: missing display"
  assert_contains "$stderr" "$fixture/layout.tsv:6: duplicates line 1"
  assert_contains "$stderr" "Error: invalid Dock layout catalog: $fixture/layout.tsv"
  assert_not_contains "$fixture/run1/events.log" 'dockutil'
  assert_not_contains "$fixture/run1/events.log" 'killall'
  [[ ! -f $fixture/state/dotfiles/dock-applied ]] \
    || scenario_fail 'run-once marker recorded for an invalid layout'
}

# The layout is read again only on a reset, so a row broken after the first
# apply would otherwise stay hidden behind the marker until then.
# shellcheck disable=SC2016  # rows keep $HOME literal; the applier expands it
test_a_broken_layout_is_reported_after_the_dock_was_applied() {
  local fixture
  fixture=$(make_fixture)
  invoke_dock "$fixture" "$fixture/run1"

  printf 'others\t$HOME/Downloads\tcarousel\tfolder\n' >"$fixture/layout.tsv"
  if invoke_dock "$fixture" "$fixture/run2"; then
    return 1
  fi
  assert_contains "$fixture/run2/stderr.log" "$fixture/layout.tsv:1: unknown view 'carousel'"
  assert_not_contains "$fixture/run2/stdout.log" 'already applied'
  assert_not_contains "$fixture/run2/events.log" 'dockutil'
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
scenario_run 'an invalid layout leaves the Dock untouched' \
  test_an_invalid_layout_leaves_the_dock_untouched
scenario_run 'a broken layout is reported after the Dock was applied' \
  test_a_broken_layout_is_reported_after_the_dock_was_applied
scenario_run 'a missing catalog fails the apply' test_missing_catalog_fails_the_apply
scenario_finish
