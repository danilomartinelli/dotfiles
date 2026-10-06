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
scenario_init dotfiles-macos-defaults-tests

make_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/_macos" "$fixture/_scripts" "$fixture/home/Library"
  cp "$REPOSITORY_ROOT/_macos/set-defaults.sh" "$fixture/_macos/set-defaults.sh"
  cp "$REPOSITORY_ROOT/_macos/defaults-rules.sh" "$fixture/_macos/defaults-rules.sh"
  cp "$REPOSITORY_ROOT/_scripts/catalog.sh" "$fixture/_scripts/catalog.sh"
  cp "$REPOSITORY_ROOT/_scripts/installer-output.sh" "$fixture/_scripts/installer-output.sh"
  chmod +x "$fixture/_macos/set-defaults.sh"
  cat >"$fixture/_macos/defaults.tsv" <<'EOF'
# test catalog
-g	ApplePressAndHoldEnabled	bool	false
NSGlobalDomain	KeyRepeat	int	1
com.apple.finder	FXPreferredViewStyle	string	Nlsv
com.apple.finder	NewWindowTargetPath	string	file://$HOME/
EOF

  scenario_write_executable "$fixture/fake-bin/defaults" <<'EOF'
#!/bin/sh
printf 'defaults %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
EOF
  scenario_write_executable "$fixture/fake-bin/networksetup" <<'EOF'
#!/bin/sh
printf 'networksetup %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_NETWORKSETUP:-0}"
EOF
  scenario_write_executable "$fixture/fake-bin/sudo" <<'EOF'
#!/bin/sh
# $0 is sudo; $1 is the flag or command (do not shift the command away).
if [ "$1" = -n ] || [ "$1" = -v ]; then
  exit "${FAIL_SUDO:-0}"
fi
exec "$@"
EOF
  scenario_write_executable "$fixture/fake-bin/chflags" <<'EOF'
#!/bin/sh
printf 'chflags %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
EOF
  scenario_write_executable "$fixture/fake-bin/xattr" <<'EOF'
#!/bin/sh
printf 'xattr %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
EOF
  stub_killall "$fixture/fake-bin"

  printf '%s\n' "$fixture"
}

invoke_defaults() {
  local fixture=$1
  fixture_run "$fixture" \
    DOTFILES_MACOS_DEFAULTS_CATALOG="$fixture/_macos/defaults.tsv" \
    -- "$fixture/_macos/set-defaults.sh"
}

test_catalog_order_and_expansion() {
  local fixture

  fixture=$(make_fixture)
  invoke_defaults "$fixture"
  assert_before "$fixture/events.log" \
    'defaults write -g ApplePressAndHoldEnabled -bool false' \
    'defaults write NSGlobalDomain KeyRepeat -int 1'
  assert_before "$fixture/events.log" \
    'defaults write com.apple.finder FXPreferredViewStyle -string Nlsv' \
    "defaults write com.apple.finder NewWindowTargetPath -string file://$fixture/home/"
  assert_contains "$fixture/events.log" 'killall Finder'
  assert_contains "$fixture/events.log" 'chflags nohidden'
}

test_no_dns_mutation() {
  local fixture

  fixture=$(make_fixture)
  invoke_defaults "$fixture"
  # DNS is owned by the OS/Tailscale/VPN; the apply must never touch it.
  if grep -q 'networksetup' "$fixture/events.log"; then
    return 1
  fi
  assert_contains "$fixture/events.log" 'killall Finder'
}

# `defaults write` accepts a malformed value and writes 0 or a truncation in its
# place, so the value is checked against its type before anything is written,
# and a fault anywhere in the catalog writes nothing at all.
test_an_invalid_catalog_writes_nothing() {
  local catalog fixture

  fixture=$(make_fixture)
  catalog=$fixture/_macos/defaults.tsv
  cat >"$catalog" <<'EOF'
NSGlobalDomain	KeyRepeat	int	1
NSGlobalDomain	InitialKeyRepeat	array	1
NSGlobalDomain	AppleKeyboardUIMode	int	abc
com.apple.dock	autohide-delay	float	x1
com.apple.dock	autohide	bool	maybe
com.apple.finder	NewWindowTargetPath	string	file://$HOEM/
-g	KeyRepeat	int	2
com.apple.finder	ShowStatusBar	bool
EOF
  if invoke_defaults "$fixture"; then
    return 1
  fi

  assert_contains "$fixture/stderr.log" "$catalog:2: unknown type 'array'"
  assert_contains "$fixture/stderr.log" "$catalog:3: int value is not an integer: 'abc'"
  assert_contains "$fixture/stderr.log" "$catalog:4: float value is not a number: 'x1'"
  assert_contains "$fixture/stderr.log" "$catalog:5: bool value is not true or false: 'maybe'"
  assert_contains "$fixture/stderr.log" "$catalog:6: unknown placeholder \$HOEM"
  assert_contains "$fixture/stderr.log" "$catalog:7: duplicates line 1"
  assert_contains "$fixture/stderr.log" "$catalog:8: missing value"
  assert_contains "$fixture/stderr.log" "Error: invalid defaults catalog: $catalog"
  assert_not_contains "$fixture/events.log" 'defaults write'
  assert_not_contains "$fixture/events.log" 'killall'
  [[ ! -d $fixture/home/Downloads/Screenshots ]] \
    || scenario_fail 'screenshot directory created for an invalid catalog'
}

scenario_run 'catalog applies in order with HOME expansion' test_catalog_order_and_expansion
scenario_run 'the apply never mutates DNS' test_no_dns_mutation
scenario_run 'an invalid catalog writes nothing' test_an_invalid_catalog_writes_nothing
scenario_finish
