#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-homebrew-bundle-tests

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/homebrew" "$fixture/fake-bin"
  cp "$REPOSITORY_ROOT/homebrew/_bundle.sh" "$fixture/homebrew/_bundle.sh"
  sed \
    -e "s|/opt/homebrew|$fixture/platform/opt/homebrew|g" \
    -e "s|/usr/local|$fixture/platform/usr/local|g" \
    -e "s|/home/linuxbrew/.linuxbrew|$fixture/platform/home/linuxbrew/.linuxbrew|g" \
    "$REPOSITORY_ROOT/homebrew/_availability.sh" \
    >"$fixture/homebrew/_availability.sh"
  chmod +x "$fixture/homebrew/_bundle.sh" "$fixture/homebrew/_availability.sh"
  printf '%s\n' "tap 'xo/xo'" "brew 'archiver'" >"$fixture/Brewfile"

  scenario_write_executable "$fixture/fake-bin/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
case "$1" in
  trust)
    exit "${FAIL_BREW_TRUST:-0}"
    ;;
  bundle)
    exit "${FAIL_BREW_BUNDLE:-0}"
    ;;
esac
exit 0
EOF

  printf '%s\n' "$fixture"
}

invoke_bundle() {
  local fixture=$1
  shift
  scenario_capture "$fixture" env \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    DOTFILES_ROOT="$fixture" \
    "$fixture/homebrew/_bundle.sh" "$@"
}

test_trust_then_bundle() {
  local fixture

  fixture=$(make_fixture)
  invoke_bundle "$fixture" --brew "$fixture/fake-bin/brew" --file "$fixture/Brewfile"
  assert_before "$fixture/events.log" 'brew tap nikitabobko/tap' 'brew trust --tap nikitabobko/tap'
  assert_before "$fixture/events.log" 'brew trust --tap nikitabobko/tap' "brew bundle --file $fixture/Brewfile"
}

test_trust_advisory_bundle_critical() {
  local fixture

  fixture=$(make_fixture)
  export FAIL_BREW_TRUST=1
  invoke_bundle "$fixture" --brew "$fixture/fake-bin/brew" --file "$fixture/Brewfile"
  unset FAIL_BREW_TRUST
  assert_contains "$fixture/stderr.log" 'trust nikitabobko/tap failed'
  assert_contains "$fixture/events.log" 'brew bundle --file'

  fixture=$(make_fixture)
  export FAIL_BREW_BUNDLE=1
  if invoke_bundle "$fixture" --brew "$fixture/fake-bin/brew" --file "$fixture/Brewfile"; then
    return 1
  fi
  unset FAIL_BREW_BUNDLE
}

scenario_run 'bundle trusts then reconciles the Brewfile' test_trust_then_bundle
scenario_run 'trust stays advisory while bundle remains critical' test_trust_advisory_bundle_critical
scenario_finish
