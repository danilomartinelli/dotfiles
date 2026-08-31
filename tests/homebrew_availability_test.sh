#!/usr/bin/env bash

set -u

TEST_PATH=${BASH_SOURCE[0]}
TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
scenario_init dotfiles-homebrew-availability-tests
TEST_ROOT=$SCENARIO_ROOT

new_fixture() {
  FIXTURE=$(mktemp -d "$TEST_ROOT/fixture.XXXXXX")
  FAKE_BIN=$FIXTURE/fake-bin
  PLATFORM_ROOT=$FIXTURE/platform
  OPT_PREFIX=$PLATFORM_ROOT/opt/homebrew
  USR_PREFIX=$PLATFORM_ROOT/usr/local
  LINUX_PREFIX=$PLATFORM_ROOT/home/linuxbrew/.linuxbrew
  VALID_PREFIX=$FIXTURE/valid-prefix
  STDOUT_LOG=$FIXTURE/stdout.log
  STDERR_LOG=$FIXTURE/stderr.log
  INSTALL_LOG=$FIXTURE/install.log
  BREW_TEMPLATE=$FIXTURE/brew-template

  mkdir -p "$FIXTURE/homebrew" "$FIXTURE/_scripts" "$FAKE_BIN" "$VALID_PREFIX" "$FIXTURE/tmp"
  stub_uname "$FAKE_BIN"
  : >"$INSTALL_LOG"

  cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$FIXTURE/homebrew/_availability.sh"
  cp "$REPOSITORY_ROOT/homebrew/install.sh" "$FIXTURE/homebrew/install.sh"
  cp "$REPOSITORY_ROOT/_scripts/installer-preamble.sh" "$FIXTURE/_scripts/installer-preamble.sh"
  cp "$REPOSITORY_ROOT/_scripts/catalog.sh" "$FIXTURE/_scripts/catalog.sh"
  cp "$REPOSITORY_ROOT/_scripts/installer-output.sh" "$FIXTURE/_scripts/installer-output.sh"

  cat >"$BREW_TEMPLATE" <<'EOF'
#!/bin/sh
if [ "$1" != --prefix ]; then
  exit 0
fi

case "${BREW_TEST_PREFIX_MODE:-valid}" in
  failed)
    exit 1
    ;;
  relative)
    printf '%s\n' relative/prefix
    ;;
  multiline)
    printf '%s\n%s\n' "$BREW_TEST_PREFIX" /second/prefix
    ;;
  *)
    printf '%s\n' "$BREW_TEST_PREFIX"
    ;;
esac
EOF

  cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' curl >> "$BREW_TEST_INSTALL_LOG"
installer_file=
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    shift
    installer_file=$1
  fi
  shift
done

cat > "$installer_file" <<'INSTALLER'
#!/usr/bin/env bash
# Homebrew fixture installer
if [[ ${BREW_TEST_INSTALL_MODE:-install} == install ]]; then
  cp "$BREW_TEST_TEMPLATE" "$BREW_TEST_INSTALL_TARGET"
  chmod +x "$BREW_TEST_INSTALL_TARGET"
fi
INSTALLER
EOF

  chmod +x \
    "$FIXTURE/homebrew/_availability.sh" \
    "$FIXTURE/homebrew/install.sh" \
    "$BREW_TEMPLATE" \
    "$FAKE_BIN/curl"

  BREW_TEST_PREFIX=$VALID_PREFIX
  BREW_TEST_PREFIX_MODE=valid
  FAKE_UNAME=Darwin
  BREW_TEST_INSTALL_MODE=install
  BREW_TEST_INSTALL_TARGET=$FAKE_BIN/brew
}

install_fake_brew() {
  local target=$1
  mkdir -p "$(dirname -- "$target")"
  cp "$BREW_TEMPLATE" "$target"
  chmod +x "$target"
}

capture_module() {
  CAPTURED_STATUS=0
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_HOMEBREW_ROOT="$PLATFORM_ROOT" \
    BREW_TEST_PREFIX="$BREW_TEST_PREFIX" \
    BREW_TEST_PREFIX_MODE="$BREW_TEST_PREFIX_MODE" \
    "$FIXTURE/homebrew/_availability.sh" "$@" \
    >"$STDOUT_LOG" 2>"$STDERR_LOG" || CAPTURED_STATUS=$?
}

capture_installer() {
  CAPTURED_STATUS=0
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    TMPDIR="$FIXTURE/tmp" \
    DOTFILES_HOMEBREW_ROOT="$PLATFORM_ROOT" \
    BREW_TEST_PREFIX="$BREW_TEST_PREFIX" \
    BREW_TEST_PREFIX_MODE="$BREW_TEST_PREFIX_MODE" \
    FAKE_UNAME="$FAKE_UNAME" \
    BREW_TEST_INSTALL_LOG="$INSTALL_LOG" \
    BREW_TEST_INSTALL_MODE="$BREW_TEST_INSTALL_MODE" \
    BREW_TEST_INSTALL_TARGET="$BREW_TEST_INSTALL_TARGET" \
    BREW_TEST_TEMPLATE="$BREW_TEMPLATE" \
    "$FIXTURE/homebrew/install.sh" \
    >"$STDOUT_LOG" 2>"$STDERR_LOG" || CAPTURED_STATUS=$?
}

test_binary_precedence() {
  new_fixture
  install_fake_brew "$FAKE_BIN/brew"
  install_fake_brew "$OPT_PREFIX/bin/brew"

  capture_module binary
  assert_equal 0 "$CAPTURED_STATUS" 'PATH binary status'
  assert_equal "$FAKE_BIN/brew" "$(<"$STDOUT_LOG")" 'PATH binary precedence'

  rm "$FAKE_BIN/brew"
  install_fake_brew "$USR_PREFIX/bin/brew"
  install_fake_brew "$LINUX_PREFIX/bin/brew"

  capture_module binary
  assert_equal "$OPT_PREFIX/bin/brew" "$(<"$STDOUT_LOG")" 'Apple Silicon candidate precedence'

  chmod -x "$OPT_PREFIX/bin/brew"
  capture_module binary
  assert_equal "$USR_PREFIX/bin/brew" "$(<"$STDOUT_LOG")" 'Intel macOS candidate precedence'

  chmod -x "$USR_PREFIX/bin/brew"
  capture_module binary
  assert_equal "$LINUX_PREFIX/bin/brew" "$(<"$STDOUT_LOG")" 'Linux candidate precedence'
}

test_prefix_validation() {
  new_fixture
  install_fake_brew "$FAKE_BIN/brew"

  capture_module prefix
  assert_equal 0 "$CAPTURED_STATUS" 'valid prefix status'
  assert_equal "$VALID_PREFIX" "$(<"$STDOUT_LOG")" 'valid prefix output'

  BREW_TEST_PREFIX_MODE=failed
  capture_module prefix
  assert_equal 1 "$CAPTURED_STATUS" 'failed brew status'
  assert_empty "$STDOUT_LOG"

  BREW_TEST_PREFIX_MODE=relative
  capture_module prefix
  assert_equal 1 "$CAPTURED_STATUS" 'relative prefix status'
  assert_empty "$STDOUT_LOG"

  BREW_TEST_PREFIX_MODE=multiline
  capture_module prefix
  assert_equal 1 "$CAPTURED_STATUS" 'multiline prefix status'
  assert_empty "$STDOUT_LOG"

  BREW_TEST_PREFIX_MODE=valid
  BREW_TEST_PREFIX=$FIXTURE/missing-prefix
  capture_module prefix
  assert_equal 1 "$CAPTURED_STATUS" 'missing prefix status'
  assert_empty "$STDOUT_LOG"
}

test_prefix_fallbacks() {
  new_fixture
  capture_module prefix
  assert_equal 1 "$CAPTURED_STATUS" 'missing Homebrew strict status'
  assert_empty "$STDOUT_LOG"

  mkdir -p "$OPT_PREFIX"
  capture_module prefix --fallback
  assert_equal 0 "$CAPTURED_STATUS" 'Apple Silicon fallback status'
  assert_equal "$OPT_PREFIX" "$(<"$STDOUT_LOG")" 'Apple Silicon fallback'

  rmdir "$OPT_PREFIX"
  mkdir -p "$USR_PREFIX/Homebrew"
  capture_module prefix --fallback
  assert_equal "$USR_PREFIX" "$(<"$STDOUT_LOG")" 'Intel macOS fallback'

  rmdir "$USR_PREFIX/Homebrew"
  capture_module prefix --fallback
  assert_equal "$USR_PREFIX" "$(<"$STDOUT_LOG")" 'final startup fallback'
}

test_usage_contract() {
  new_fixture
  capture_module
  assert_equal 2 "$CAPTURED_STATUS" 'missing arguments status'
  assert_contains "$STDERR_LOG" 'binary|prefix [--fallback]'

  capture_module prefix --invalid
  assert_equal 2 "$CAPTURED_STATUS" 'invalid arguments status'
  assert_contains "$STDERR_LOG" 'binary|prefix [--fallback]'
}

test_installer_verification() {
  new_fixture
  install_fake_brew "$FAKE_BIN/brew"
  capture_installer
  assert_equal 0 "$CAPTURED_STATUS" 'existing Homebrew installer status'
  assert_not_contains "$INSTALL_LOG" curl

  new_fixture
  capture_installer
  assert_equal 0 "$CAPTURED_STATUS" 'fresh Homebrew installer status'
  assert_contains "$INSTALL_LOG" curl
  assert_contains "$STDOUT_LOG" 'Homebrew installed successfully.'
  [[ -x $BREW_TEST_INSTALL_TARGET ]] || scenario_fail 'Downloaded installer did not create brew'

  new_fixture
  BREW_TEST_INSTALL_MODE=noop
  capture_installer
  assert_equal 1 "$CAPTURED_STATUS" 'post-install verification status'
  assert_contains "$STDERR_LOG" 'Homebrew installation completed, but brew was not found'
}

scenario_run 'the brew binary is found by precedence' test_binary_precedence
scenario_run 'a prefix is validated before it is trusted' test_prefix_validation
scenario_run 'prefix fallbacks follow the platform roots' test_prefix_fallbacks
scenario_run 'the usage contract rejects unknown arguments' test_usage_contract
scenario_run 'the installer verifies brew afterwards' test_installer_verification
scenario_finish
