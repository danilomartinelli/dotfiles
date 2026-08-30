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
scenario_init dotfiles-homebrew-maintenance-tests

make_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/homebrew"
  cp "$REPOSITORY_ROOT/homebrew/_maintenance.sh" "$fixture/homebrew/_maintenance.sh"
  cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$fixture/homebrew/_availability.sh"
  chmod +x "$fixture/homebrew/_maintenance.sh" "$fixture/homebrew/_availability.sh"

  stub_brew "$fixture/fake-bin"

  printf '%s\n' "$fixture"
}

invoke_maintenance() {
  local fixture=$1
  shift
  fixture_run "$fixture" "$@" \
    -- "$fixture/homebrew/_maintenance.sh" --brew "$fixture/fake-bin/brew"
}

test_unused_legacy_tap_is_removed() {
  local fixture
  fixture=$(make_fixture)
  invoke_maintenance "$fixture" FAKE_BREW_TAPS=xo/xo

  assert_contains "$fixture/events.log" 'brew untap xo/xo'
  assert_contains "$fixture/stdout.log" 'Removed unused legacy Homebrew tap: xo/xo'
}

test_absent_tap_is_ignored() {
  local fixture
  fixture=$(make_fixture)
  invoke_maintenance "$fixture"

  assert_not_contains "$fixture/events.log" 'brew list'
  assert_not_contains "$fixture/events.log" 'brew untap'
}

test_tap_with_installed_item_is_preserved() {
  local fixture
  fixture=$(make_fixture)
  invoke_maintenance "$fixture" FAKE_BREW_TAPS=xo/xo FAKE_BREW_FORMULAE=xo/xo/usql

  assert_not_contains "$fixture/events.log" 'brew untap'
  assert_contains "$fixture/stderr.log" 'preserving legacy tap xo/xo because it still owns installed packages'
}

test_inspection_failure_preserves_tap() {
  local fixture
  fixture=$(make_fixture)
  invoke_maintenance "$fixture" FAKE_BREW_TAPS=xo/xo FAIL_BREW_LIST=1

  assert_not_contains "$fixture/events.log" 'brew untap'
  assert_contains "$fixture/stderr.log" 'could not inspect installed packages; preserving legacy tap xo/xo'
}

scenario_run 'unused legacy taps are removed' test_unused_legacy_tap_is_removed
scenario_run 'absent legacy taps are ignored' test_absent_tap_is_ignored
scenario_run 'legacy taps with installed packages are preserved' test_tap_with_installed_item_is_preserved
scenario_run 'package inspection failures preserve legacy taps' test_inspection_failure_preserves_tap
scenario_finish
