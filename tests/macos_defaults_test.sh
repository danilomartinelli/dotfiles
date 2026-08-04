#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-macos-defaults-tests

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/_macos" "$fixture/fake-bin" "$fixture/home/Library"
  cp "$REPOSITORY_ROOT/_macos/set-defaults.sh" "$fixture/_macos/set-defaults.sh"
  chmod +x "$fixture/_macos/set-defaults.sh"
  cat >"$fixture/_macos/defaults.tsv" <<'EOF'
# test catalog
-g	ApplePressAndHoldEnabled	bool	false
NSGlobalDomain	KeyRepeat	int	1
com.apple.finder	FXPreferredViewStyle	string	Nlsv
com.apple.finder	NewWindowTargetPath	string	file://$HOME/
EOF

  scenario_write_executable "$fixture/fake-bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Darwin
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
  scenario_write_executable "$fixture/fake-bin/killall" <<'EOF'
#!/bin/sh
printf 'killall %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
EOF

  printf '%s\n' "$fixture"
}

invoke_defaults() {
  local fixture=$1
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    DOTFILES_MACOS_DEFAULTS_CATALOG="$fixture/_macos/defaults.tsv" \
    "$fixture/_macos/set-defaults.sh"
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
  assert_before "$fixture/events.log" \
    "defaults write com.apple.finder NewWindowTargetPath -string file://$fixture/home/" \
    'networksetup -setdnsservers'
  assert_contains "$fixture/events.log" 'killall Finder'
  assert_contains "$fixture/events.log" 'chflags nohidden'
}

test_dns_advisory_without_sudo() {
  local fixture

  fixture=$(make_fixture)
  export FAIL_SUDO=1
  invoke_defaults "$fixture"
  unset FAIL_SUDO
  assert_contains "$fixture/stderr.log" 'Skipping DNS configuration'
  assert_contains "$fixture/events.log" 'killall Finder'
}

test_invalid_type_fails() {
  local fixture

  fixture=$(make_fixture)
  printf 'NSGlobalDomain\tKeyRepeat\tarray\t1\n' >"$fixture/_macos/defaults.tsv"
  if invoke_defaults "$fixture"; then
    return 1
  fi
  assert_contains "$fixture/stderr.log" "unknown catalog type 'array'"
}

scenario_run 'catalog applies in order with HOME expansion' test_catalog_order_and_expansion
scenario_run 'DNS stays advisory without sudo' test_dns_advisory_without_sudo
scenario_run 'invalid catalog types fail the apply' test_invalid_type_fails
scenario_finish
