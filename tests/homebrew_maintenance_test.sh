#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-homebrew-maintenance-tests

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/homebrew" "$fixture/fake-bin"
  cp "$REPOSITORY_ROOT/homebrew/_maintenance.sh" "$fixture/homebrew/_maintenance.sh"
  cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$fixture/homebrew/_availability.sh"
  chmod +x "$fixture/homebrew/_maintenance.sh" "$fixture/homebrew/_availability.sh"

  scenario_write_executable "$fixture/fake-bin/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
case "$1" in
  tap)
    [ -n "${FAKE_BREW_TAPS:-}" ] && printf '%s\n' "$FAKE_BREW_TAPS"
    ;;
  list)
    if [ "${FAIL_BREW_LIST:-0}" -ne 0 ]; then
      exit "$FAIL_BREW_LIST"
    fi
    case "$2" in
      --formula) [ -n "${FAKE_BREW_FORMULAE:-}" ] && printf '%s\n' "$FAKE_BREW_FORMULAE" ;;
      --cask) [ -n "${FAKE_BREW_CASKS:-}" ] && printf '%s\n' "$FAKE_BREW_CASKS" ;;
    esac
    exit 0
    ;;
  untap)
    exit "${FAIL_BREW_UNTAP:-0}"
    ;;
esac
EOF

  printf '%s\n' "$fixture"
}

invoke_maintenance() {
  local fixture=$1
  scenario_capture "$fixture" env \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    "$fixture/homebrew/_maintenance.sh" --brew "$fixture/fake-bin/brew"
}

test_unused_legacy_tap_is_removed() {
  local fixture
  fixture=$(make_fixture)
  export FAKE_BREW_TAPS=xo/xo
  invoke_maintenance "$fixture"
  unset FAKE_BREW_TAPS

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
  export FAKE_BREW_TAPS=xo/xo FAKE_BREW_FORMULAE=xo/xo/usql
  invoke_maintenance "$fixture"
  unset FAKE_BREW_TAPS FAKE_BREW_FORMULAE

  assert_not_contains "$fixture/events.log" 'brew untap'
  assert_contains "$fixture/stderr.log" 'preserving legacy tap xo/xo because it still owns installed packages'
}

test_inspection_failure_preserves_tap() {
  local fixture
  fixture=$(make_fixture)
  export FAKE_BREW_TAPS=xo/xo FAIL_BREW_LIST=1
  invoke_maintenance "$fixture"
  unset FAKE_BREW_TAPS FAIL_BREW_LIST

  assert_not_contains "$fixture/events.log" 'brew untap'
  assert_contains "$fixture/stderr.log" 'could not inspect installed packages; preserving legacy tap xo/xo'
}

scenario_run 'unused legacy taps are removed' test_unused_legacy_tap_is_removed
scenario_run 'absent legacy taps are ignored' test_absent_tap_is_ignored
scenario_run 'legacy taps with installed packages are preserved' test_tap_with_installed_item_is_preserved
scenario_run 'package inspection failures preserve legacy taps' test_inspection_failure_preserves_tap
scenario_finish
