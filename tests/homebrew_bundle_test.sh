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
scenario_init dotfiles-homebrew-bundle-tests

make_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/homebrew"
  cp "$REPOSITORY_ROOT/homebrew/_bundle.sh" "$fixture/homebrew/_bundle.sh"
  cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$fixture/homebrew/_availability.sh"
  chmod +x "$fixture/homebrew/_bundle.sh" "$fixture/homebrew/_availability.sh"
  printf '%s\n' "tap 'xo/xo'" "brew 'archiver'" >"$fixture/Brewfile"

  stub_brew "$fixture/fake-bin"

  printf '%s\n' "$fixture"
}

# Mirrors fixture_run: KEY=value pairs before `--` reach this run only, and
# everything after it is passed to the module as arguments.
invoke_bundle() {
  local fixture=$1
  shift
  local -a overrides=()

  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  shift

  fixture_run "$fixture" \
    DOTFILES_ROOT="$fixture" \
    DOTFILES_HOMEBREW_ROOT="$fixture/platform" \
    ${overrides[@]+"${overrides[@]}"} \
    -- "$fixture/homebrew/_bundle.sh" "$@"
}

test_trust_then_bundle() {
  local fixture

  fixture=$(make_fixture)
  invoke_bundle "$fixture" -- --brew "$fixture/fake-bin/brew" --file "$fixture/Brewfile"
  assert_before "$fixture/events.log" 'brew tap nikitabobko/tap' 'brew trust --tap nikitabobko/tap'
  assert_before "$fixture/events.log" 'brew tap psviderski/tap' 'brew trust --tap psviderski/tap'
  assert_before "$fixture/events.log" 'brew tap vjeantet/tap' 'brew trust --tap vjeantet/tap'
  assert_before "$fixture/events.log" 'brew trust --tap psviderski/tap' "brew bundle --file $fixture/Brewfile"
  assert_before "$fixture/events.log" 'brew trust --tap vjeantet/tap' "brew bundle --file $fixture/Brewfile"
  assert_before "$fixture/events.log" 'brew trust --tap nikitabobko/tap' "brew bundle --file $fixture/Brewfile"
}

test_trust_advisory_bundle_critical() {
  local fixture

  fixture=$(make_fixture)
  invoke_bundle "$fixture" FAIL_BREW_TRUST=1 \
    -- --brew "$fixture/fake-bin/brew" --file "$fixture/Brewfile"
  assert_contains "$fixture/stderr.log" 'trust nikitabobko/tap failed'
  assert_contains "$fixture/events.log" 'brew bundle --file'

  fixture=$(make_fixture)
  if invoke_bundle "$fixture" --brew "$fixture/fake-bin/brew" --file "$fixture/Brewfile"; then
    return 1
  fi
}

scenario_run 'bundle trusts then reconciles the Brewfile' test_trust_then_bundle
scenario_run 'trust stays advisory while bundle remains critical' test_trust_advisory_bundle_critical
scenario_finish
