#!/usr/bin/env bash

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPOSITORY_ROOT="$(cd "$TEST_DIR/.." && pwd -P)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-setup-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

tests_run=0
tests_failed=0

fail_assertion() {
  printf '    %s\n' "$1" >&2
  return 1
}

assert_contains() {
  local file
  local expected

  file=$1
  expected=$2
  grep -Fq "$expected" "$file" || fail_assertion "Expected $file to contain: $expected"
}

assert_not_contains() {
  local file
  local unexpected

  file=$1
  unexpected=$2
  if grep -Fq "$unexpected" "$file"; then
    fail_assertion "Expected $file not to contain: $unexpected"
  fi
}

assert_count() {
  local file
  local pattern
  local expected
  local actual

  file=$1
  pattern=$2
  expected=$3
  actual=$(grep -Fc "$pattern" "$file" || true)
  [ "$actual" -eq "$expected" ] || fail_assertion "Expected $expected occurrences of '$pattern' in $file, got $actual"
}

assert_before() {
  local file
  local first_pattern
  local second_pattern
  local first_line
  local second_line

  file=$1
  first_pattern=$2
  second_pattern=$3
  first_line=$(grep -nF "$first_pattern" "$file" | head -n 1 | cut -d: -f1)
  second_line=$(grep -nF "$second_pattern" "$file" | head -n 1 | cut -d: -f1)

  [ -n "$first_line" ] || fail_assertion "Missing '$first_pattern' in $file"
  [ -n "$second_line" ] || fail_assertion "Missing '$second_pattern' in $file"
  [ "$first_line" -lt "$second_line" ] || fail_assertion "Expected '$first_pattern' before '$second_pattern' in $file"
}

write_fixture_scripts() {
  local fixture
  fixture=$1

  cat > "$fixture/fake-bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Darwin}"
EOF

  cat > "$fixture/fake-bin/git" <<'EOF'
#!/bin/sh
printf 'git %s\n' "$*" >> "$SETUP_TEST_LOG"
case " $* " in
  *' rev-parse '*) exit "${FAIL_GIT_CHECKOUT:-0}" ;;
  *' pull '*) exit "${FAIL_GIT_PULL:-0}" ;;
esac
exit 0
EOF

  cat > "$fixture/fake-bin/brew-template" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$SETUP_TEST_LOG"
case "$1" in
  --prefix)
    printf '%s\n' "$FAKE_BREW_PREFIX"
    ;;
  update)
    exit "${FAIL_BREW_UPDATE:-0}"
    ;;
  upgrade)
    exit "${FAIL_BREW_UPGRADE:-0}"
    ;;
  tap)
    exit "${FAIL_BREW_TAP:-0}"
    ;;
  bundle)
    exit "${FAIL_BREW_BUNDLE:-0}"
    ;;
esac
exit 0
EOF

  cat > "$fixture/homebrew/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' homebrew-installer >> "$SETUP_TEST_LOG"
if [ -n "${SETUP_TEST_BREW_TARGET:-}" ]; then
  cp "$SETUP_TEST_BREW_TEMPLATE" "$SETUP_TEST_BREW_TARGET"
  chmod +x "$SETUP_TEST_BREW_TARGET"
fi
exit "${FAIL_HOMEBREW_INSTALL:-0}"
EOF

  cat > "$fixture/_macos/set-defaults.sh" <<'EOF'
#!/bin/sh
printf '%s\n' macos-defaults >> "$SETUP_TEST_LOG"
exit "${FAIL_DEFAULTS:-0}"
EOF

  cat > "$fixture/_macos/set-hostname.sh" <<'EOF'
#!/bin/sh
printf '%s\n' hostname >> "$SETUP_TEST_LOG"
exit "${FAIL_HOSTNAME:-0}"
EOF

  cat > "$fixture/alpha/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-alpha >> "$SETUP_TEST_LOG"
exit "${FAIL_TOPIC_ALPHA:-0}"
EOF

  cat > "$fixture/zulu/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-zulu >> "$SETUP_TEST_LOG"
exit "${FAIL_TOPIC_ZULU:-0}"
EOF

  cat > "$fixture/_ignored/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-ignored >> "$SETUP_TEST_LOG"
EOF

  cat > "$fixture/fake-bin/editor" <<'EOF'
#!/bin/sh
printf 'editor %s\n' "$*" >> "$SETUP_TEST_LOG"
EOF

  chmod +x \
    "$fixture/fake-bin/uname" \
    "$fixture/fake-bin/git" \
    "$fixture/fake-bin/brew-template" \
    "$fixture/fake-bin/editor" \
    "$fixture/homebrew/install.sh" \
    "$fixture/_macos/set-defaults.sh" \
    "$fixture/_macos/set-hostname.sh" \
    "$fixture/alpha/install.sh" \
    "$fixture/zulu/install.sh" \
    "$fixture/_ignored/install.sh"
}

make_fixture() {
  local brew_state
  local fixture

  brew_state=${1:-present}
  fixture=$(mktemp -d "$TEST_ROOT/fixture.XXXXXX")
  mkdir -p \
    "$fixture/_scripts" \
    "$fixture/_macos" \
    "$fixture/alpha" \
    "$fixture/zulu" \
    "$fixture/_ignored" \
    "$fixture/homebrew" \
    "$fixture/git" \
    "$fixture/sample" \
    "$fixture/bin" \
    "$fixture/fake-bin" \
    "$fixture/fake-prefix/bin" \
    "$fixture/home"

  cp "$REPOSITORY_ROOT/_scripts/setup" "$fixture/_scripts/setup"
  cp "$REPOSITORY_ROOT/_scripts/bootstrap" "$fixture/_scripts/bootstrap"
  cp "$REPOSITORY_ROOT/bin/dot" "$fixture/bin/dot"
  cp "$REPOSITORY_ROOT/bin/set-defaults" "$fixture/bin/set-defaults"
  cp "$REPOSITORY_ROOT/dotfiles-root.symlink" "$fixture/dotfiles-root.symlink"
  chmod +x "$fixture/_scripts/setup" "$fixture/_scripts/bootstrap" "$fixture/bin/dot" "$fixture/bin/set-defaults" "$fixture/dotfiles-root.symlink"

  printf '%s\n' '# local environment' > "$fixture/.localrc.example"
  printf '%s\n' '# Brewfile fixture' > "$fixture/Brewfile"
  printf '%s\n' '[user]' > "$fixture/git/gitconfig.local.symlink.example"
  printf '%s\n' '[user]' > "$fixture/git/gitconfig.local.symlink"
  printf '%s\n' 'fixture config' > "$fixture/sample/config.symlink"

  write_fixture_scripts "$fixture"
  if [ "$brew_state" = present ]; then
    cp "$fixture/fake-bin/brew-template" "$fixture/fake-bin/brew"
    chmod +x "$fixture/fake-bin/brew"
  fi

  printf '%s\n' "$fixture"
}

invoke() {
  local fixture
  shift_count=1
  fixture=$1
  shift "$shift_count"

  HOME="$fixture/home" \
  PATH="$fixture/fake-bin:/usr/bin:/bin" \
  SETUP_TEST_LOG="$fixture/events.log" \
  FAKE_BREW_PREFIX="$fixture/fake-prefix" \
  EDITOR="$fixture/fake-bin/editor" \
  "$@" > "$fixture/stdout.log" 2> "$fixture/stderr.log"
}

test_setup_usage() {
  local fixture
  local status

  fixture=$(make_fixture)
  if invoke "$fixture" "$fixture/_scripts/setup" invalid; then
    return 1
  else
    status=$?
  fi

  [ "$status" -eq 2 ]
  assert_contains "$fixture/stderr.log" 'Usage: _scripts/setup bootstrap|update'
}

test_bootstrap_sequence() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" bootstrap

  assert_before "$fixture/stdout.log" 'Git identity' 'dotfile links'
  assert_before "$fixture/stdout.log" 'dotfile links' 'macOS defaults'
  assert_before "$fixture/events.log" macos-defaults hostname
  assert_before "$fixture/events.log" hostname homebrew-installer
  assert_before "$fixture/events.log" 'brew tap xo/xo' 'brew bundle --file'
  assert_before "$fixture/events.log" 'brew bundle --file' topic-alpha
  assert_before "$fixture/events.log" topic-alpha topic-zulu
  assert_count "$fixture/events.log" homebrew-installer 1
  assert_not_contains "$fixture/events.log" 'git '
  assert_not_contains "$fixture/events.log" 'brew update'
  assert_not_contains "$fixture/events.log" 'brew upgrade'
  assert_not_contains "$fixture/events.log" topic-ignored
  assert_contains "$fixture/stdout.log" 'setup bootstrap complete'
  [ -L "$fixture/home/.localrc" ]
  [ -L "$fixture/home/.config" ]
  [ -L "$fixture/home/.dotfiles-root" ]
}

test_update_sequence_and_cwd_independence() {
  local fixture

  fixture=$(make_fixture)
  (
    cd "$TEST_ROOT" || exit 1
    invoke "$fixture" "$fixture/_scripts/setup" update
  )

  assert_before "$fixture/events.log" 'rev-parse --is-inside-work-tree' ' pull'
  assert_before "$fixture/events.log" ' pull' homebrew-installer
  assert_before "$fixture/events.log" homebrew-installer 'brew update'
  assert_before "$fixture/events.log" 'brew update' 'brew upgrade'
  assert_before "$fixture/events.log" 'brew upgrade' 'brew tap xo/xo'
  assert_before "$fixture/events.log" 'brew bundle --file' topic-alpha
  assert_not_contains "$fixture/events.log" macos-defaults
  assert_not_contains "$fixture/events.log" hostname
  assert_not_contains "$fixture/stdout.log" 'Git identity'
  assert_not_contains "$fixture/stdout.log" 'dotfile links'
  assert_contains "$fixture/stdout.log" 'setup update complete'
  [ -L "$fixture/home/.dotfiles-root" ]
}

test_advisory_failures_continue() {
  local bootstrap_fixture
  local non_git_fixture
  local update_fixture

  bootstrap_fixture=$(make_fixture)
  export FAIL_HOSTNAME=1
  invoke "$bootstrap_fixture" "$bootstrap_fixture/_scripts/setup" bootstrap
  unset FAIL_HOSTNAME
  assert_contains "$bootstrap_fixture/stderr.log" 'hostname normalization failed; continuing'
  assert_contains "$bootstrap_fixture/events.log" topic-zulu
  assert_contains "$bootstrap_fixture/stdout.log" 'setup bootstrap complete'

  update_fixture=$(make_fixture)
  export FAIL_GIT_PULL=1 FAIL_BREW_UPDATE=1 FAIL_BREW_UPGRADE=1
  invoke "$update_fixture" "$update_fixture/_scripts/setup" update
  unset FAIL_GIT_PULL FAIL_BREW_UPDATE FAIL_BREW_UPGRADE
  assert_contains "$update_fixture/stderr.log" 'checkout refresh failed; continuing'
  assert_contains "$update_fixture/stderr.log" 'Homebrew update failed; continuing'
  assert_contains "$update_fixture/stderr.log" 'Homebrew upgrade failed; continuing'
  assert_contains "$update_fixture/events.log" topic-zulu
  assert_contains "$update_fixture/stdout.log" 'setup update complete'

  non_git_fixture=$(make_fixture)
  export FAIL_GIT_CHECKOUT=1
  invoke "$non_git_fixture" "$non_git_fixture/_scripts/setup" update
  unset FAIL_GIT_CHECKOUT
  assert_contains "$non_git_fixture/stderr.log" 'is not a Git checkout'
  assert_contains "$non_git_fixture/stderr.log" 'checkout refresh failed; continuing'
  assert_not_contains "$non_git_fixture/events.log" ' pull'
  assert_contains "$non_git_fixture/events.log" topic-zulu
}

test_critical_failures_stop() {
  local defaults_fixture
  local bundle_fixture
  local homebrew_fixture
  local topic_fixture

  defaults_fixture=$(make_fixture)
  export FAIL_DEFAULTS=1
  if invoke "$defaults_fixture" "$defaults_fixture/_scripts/setup" bootstrap; then
    return 1
  fi
  unset FAIL_DEFAULTS
  assert_contains "$defaults_fixture/stderr.log" 'macOS defaults'
  assert_not_contains "$defaults_fixture/events.log" homebrew-installer
  assert_not_contains "$defaults_fixture/stdout.log" 'setup bootstrap complete'

  homebrew_fixture=$(make_fixture)
  export FAIL_HOMEBREW_INSTALL=1
  if invoke "$homebrew_fixture" "$homebrew_fixture/_scripts/setup" update; then
    return 1
  fi
  unset FAIL_HOMEBREW_INSTALL
  assert_contains "$homebrew_fixture/stderr.log" 'Homebrew available'
  assert_not_contains "$homebrew_fixture/events.log" 'brew update'
  assert_not_contains "$homebrew_fixture/events.log" topic-alpha

  bundle_fixture=$(make_fixture)
  export FAIL_BREW_BUNDLE=1
  if invoke "$bundle_fixture" "$bundle_fixture/_scripts/setup" update; then
    return 1
  fi
  unset FAIL_BREW_BUNDLE
  assert_contains "$bundle_fixture/stderr.log" 'Brewfile dependencies'
  assert_not_contains "$bundle_fixture/events.log" topic-alpha
  assert_not_contains "$bundle_fixture/stdout.log" 'setup update complete'

  topic_fixture=$(make_fixture)
  export FAIL_TOPIC_ALPHA=1
  if invoke "$topic_fixture" "$topic_fixture/_scripts/setup" update; then
    return 1
  fi
  unset FAIL_TOPIC_ALPHA
  assert_contains "$topic_fixture/stderr.log" 'topic installer: alpha/install.sh'
  assert_not_contains "$topic_fixture/events.log" topic-zulu
}

test_interactive_git_identity() {
  local fixture

  fixture=$(make_fixture)
  rm "$fixture/git/gitconfig.local.symlink"
  cat > "$fixture/git/gitconfig.local.symlink.example" <<'EOF'
[user]
  name = AUTHORNAME
  email = AUTHOREMAIL
[credential]
  helper = GIT_CREDENTIAL_HELPER
EOF

  printf '%s\n%s\n' 'Dan & Co|Ops' 'dan+test@example.com' | \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    SETUP_TEST_LOG="$fixture/events.log" \
    FAKE_BREW_PREFIX="$fixture/fake-prefix" \
    "$fixture/_scripts/setup" bootstrap > "$fixture/stdout.log" 2> "$fixture/stderr.log"

  assert_contains "$fixture/git/gitconfig.local.symlink" 'name = Dan & Co|Ops'
  assert_contains "$fixture/git/gitconfig.local.symlink" 'email = dan+test@example.com'
  assert_contains "$fixture/git/gitconfig.local.symlink" 'helper = osxkeychain'
  [ -L "$fixture/home/.gitconfig.local" ]
}

test_platform_and_fresh_homebrew() {
  local linux_fixture
  local fresh_brew_fixture

  linux_fixture=$(make_fixture)
  export FAKE_UNAME=Linux
  invoke "$linux_fixture" "$linux_fixture/_scripts/setup" bootstrap
  unset FAKE_UNAME
  assert_not_contains "$linux_fixture/events.log" macos-defaults
  assert_not_contains "$linux_fixture/events.log" hostname
  assert_contains "$linux_fixture/stdout.log" 'macOS configuration skipped on this platform'

  fresh_brew_fixture=$(make_fixture absent)
  export SETUP_TEST_BREW_TARGET="$fresh_brew_fixture/fake-bin/brew"
  export SETUP_TEST_BREW_TEMPLATE="$fresh_brew_fixture/fake-bin/brew-template"
  invoke "$fresh_brew_fixture" "$fresh_brew_fixture/_scripts/setup" update
  unset SETUP_TEST_BREW_TARGET SETUP_TEST_BREW_TEMPLATE
  [ -x "$fresh_brew_fixture/fake-bin/brew" ]
  assert_count "$fresh_brew_fixture/events.log" homebrew-installer 1
  assert_contains "$fresh_brew_fixture/events.log" 'brew bundle --file'
}

test_command_adapters() {
  local bootstrap_fixture
  local update_fixture
  local defaults_fixture
  local edit_fixture
  local edit_fixture_root

  bootstrap_fixture=$(make_fixture)
  invoke "$bootstrap_fixture" "$bootstrap_fixture/_scripts/bootstrap"
  assert_contains "$bootstrap_fixture/stdout.log" 'setup bootstrap complete'
  assert_not_contains "$bootstrap_fixture/events.log" 'git '

  update_fixture=$(make_fixture)
  invoke "$update_fixture" "$update_fixture/bin/dot"
  assert_contains "$update_fixture/stdout.log" 'setup update complete'
  assert_contains "$update_fixture/events.log" 'git -C'

  defaults_fixture=$(make_fixture)
  invoke "$defaults_fixture" "$defaults_fixture/bin/set-defaults"
  assert_count "$defaults_fixture/events.log" macos-defaults 1
  assert_not_contains "$defaults_fixture/events.log" hostname

  edit_fixture=$(make_fixture)
  edit_fixture_root=$(cd "$edit_fixture" && pwd -P)
  invoke "$edit_fixture" "$edit_fixture/bin/dot" --edit
  assert_contains "$edit_fixture/events.log" "editor $edit_fixture_root"
  assert_not_contains "$edit_fixture/events.log" 'git '
}

run_test() {
  local name
  local test_function

  name=$1
  test_function=$2
  tests_run=$((tests_run + 1))

  (set -e; "$test_function")
  test_status=$?
  if [ "$test_status" -eq 0 ]; then
    printf 'ok %d - %s\n' "$tests_run" "$name"
  else
    tests_failed=$((tests_failed + 1))
    printf 'not ok %d - %s\n' "$tests_run" "$name"
  fi
}

run_test 'setup rejects unknown modes' test_setup_usage
run_test 'bootstrap follows the identity-first phase sequence' test_bootstrap_sequence
run_test 'update follows the checkout-first sequence from any cwd' test_update_sequence_and_cwd_independence
run_test 'advisory failures warn and continue' test_advisory_failures_continue
run_test 'critical failures stop the run' test_critical_failures_stop
run_test 'bootstrap creates and links an interactive Git identity' test_interactive_git_identity
run_test 'platform skips and fresh Homebrew discovery work' test_platform_and_fresh_homebrew
run_test 'public commands adapt to the canonical modes' test_command_adapters

printf '1..%d\n' "$tests_run"
if [ "$tests_failed" -ne 0 ]; then
  printf '%d test(s) failed\n' "$tests_failed" >&2
  exit 1
fi
