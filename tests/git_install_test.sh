#!/usr/bin/env bash
#
# The Git topic's installer and the hooks every repository runs through:
# signing with the default key, and the secret scan before a commit.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/fixture.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/fixture.sh"
scenario_init dotfiles-git-install-tests

GIT_BIN=$(command -v git)

# A fixture whose home has an identity, as bootstrap leaves it, and whose
# fake-bin reaches the real git. Usage: new_fixture [--without-key]
new_fixture() {
  local fixture
  fixture=$(installer_fixture)
  ln -s "$GIT_BIN" "$fixture/fake-bin/git"
  printf '[user]\n\temail = fixture@example.invalid\n' >"$fixture/home/.gitconfig.local"
  ln -s "$REPOSITORY_ROOT/git/gitconfig.symlink" "$fixture/home/.gitconfig"
  if [ "${1-}" != --without-key ]; then
    mkdir -p "$fixture/home/.ssh"
    printf 'ssh-ed25519 AAAAfixture fixture\n' >"$fixture/home/.ssh/id_ed25519.pub"
  fi
  printf '%s\n' "$fixture"
}

local_setting() {
  "$GIT_BIN" config --file "$1/home/.gitconfig.local" --get "$2" || true
}

test_the_default_key_enables_signing() {
  local fixture
  fixture=$(new_fixture)
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/git/install.sh"

  assert_equal true "$(local_setting "$fixture" commit.gpgsign)" commit.gpgsign
  assert_equal true "$(local_setting "$fixture" tag.gpgsign)" tag.gpgsign
  assert_equal "$fixture/home/.ssh/id_ed25519.pub" \
    "$(local_setting "$fixture" user.signingkey)" user.signingkey
  assert_contains "$fixture/home/.config/git/allowed_signers" \
    'fixture@example.invalid ssh-ed25519'
}

test_an_explicit_choice_about_signing_is_kept() {
  local fixture
  fixture=$(new_fixture)
  "$GIT_BIN" config --file "$fixture/home/.gitconfig.local" commit.gpgsign false
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/git/install.sh"
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/git/install.sh"

  assert_equal false "$(local_setting "$fixture" commit.gpgsign)" commit.gpgsign
  assert_equal true "$(local_setting "$fixture" tag.gpgsign)" tag.gpgsign
}

test_signing_stays_off_without_a_key() {
  local fixture
  fixture=$(new_fixture --without-key)
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/git/install.sh"

  assert_equal '' "$(local_setting "$fixture" commit.gpgsign)" commit.gpgsign
  assert_equal '' "$(local_setting "$fixture" user.signingkey)" user.signingkey
}

# The identity file is a link into the checkout; writing a setting must not
# replace the link with a file.
test_the_identity_link_survives_the_installer() {
  local fixture
  fixture=$(new_fixture)
  mv "$fixture/home/.gitconfig.local" "$fixture/identity"
  ln -s "$fixture/identity" "$fixture/home/.gitconfig.local"
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/git/install.sh"

  [ -L "$fixture/home/.gitconfig.local" ] \
    || scenario_fail 'the identity link was replaced by a file'
  assert_contains "$fixture/identity" 'gpgsign = true'
}

test_the_installer_links_the_hooks_the_configuration_names() {
  local fixture
  fixture=$(new_fixture)
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/git/install.sh"

  assert_equal "$REPOSITORY_ROOT/git/hooks" \
    "$(readlink "$fixture/home/.config/git/hooks")" 'hooks link'
  assert_equal "$fixture/home/.config/git/hooks" \
    "$(env -u GIT_CONFIG_GLOBAL HOME="$fixture/home" "$GIT_BIN" config --type=path --get core.hooksPath)" \
    core.hooksPath
}

# git stops reading a repository's own hooks once core.hooksPath is set, for
# every hook, so each one git can run has to be handed on from here.
test_every_hook_is_the_dispatcher() {
  local hook
  for hook in applypatch-msg pre-applypatch post-applypatch pre-commit \
    pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase \
    post-checkout post-merge pre-push post-rewrite pre-auto-gc push-to-checkout; do
    assert_equal _dispatch "$(readlink "$REPOSITORY_ROOT/git/hooks/$hook")" "target of $hook"
  done
}

# A repository with one staged file, and a fake gitleaks that records how it
# was called. Usage: hook_fixture
hook_fixture() {
  local fixture
  fixture=$(new_fixture)
  scenario_write_executable "$fixture/fake-bin/gitleaks" <<'GITLEAKS'
#!/bin/sh
printf 'gitleaks %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
exit "${FAIL_GITLEAKS:-0}"
GITLEAKS
  "$GIT_BIN" init -q "$fixture/repository"
  printf '%s\n' "$fixture"
}

# Usage: run_hook <fixture> <hook> [KEY=value ...] [-- argument...]
run_hook() {
  local fixture=$1
  local hook=$2
  shift 2
  local -a overrides=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  [ "$#" -eq 0 ] || shift

  (
    cd "$fixture/repository" || exit 1
    fixture_run "$fixture" ${overrides[@]+"${overrides[@]}"} \
      -- "$REPOSITORY_ROOT/git/hooks/$hook" "$@"
  )
}

test_a_commit_scans_the_staged_changes() {
  local fixture
  fixture=$(hook_fixture)
  run_hook "$fixture" pre-commit

  assert_contains "$fixture/events.log" 'gitleaks git --pre-commit --staged --redact'
}

test_a_finding_stops_the_commit_before_the_repository_hook() {
  local fixture
  fixture=$(hook_fixture)
  scenario_write_executable "$fixture/repository/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
printf 'repository hook\n' >>"$SCENARIO_EVENT_LOG"
HOOK

  assert_fails_with_status 1 run_hook "$fixture" pre-commit FAIL_GITLEAKS=1
  assert_contains "$fixture/stderr.log" 'gitleaks found a secret'
  assert_not_contains "$fixture/events.log" 'repository hook'
}

test_the_repository_hook_runs_with_its_arguments_and_input() {
  local fixture
  fixture=$(hook_fixture)
  scenario_write_executable "$fixture/repository/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
printf 'pre-push %s: %s\n' "$*" "$(cat)" >>"$SCENARIO_EVENT_LOG"
exit 7
HOOK

  printf 'refs input' >"$fixture/input"
  assert_fails_with_status 7 run_hook "$fixture" pre-push -- origin url <"$fixture/input"
  assert_contains "$fixture/events.log" 'pre-push origin url: refs input'
  assert_not_contains "$fixture/events.log" gitleaks
}

test_a_missing_scanner_or_repository_hook_is_not_an_error() {
  local fixture
  fixture=$(hook_fixture)
  rm "$fixture/fake-bin/gitleaks"
  run_hook "$fixture" pre-commit
  run_hook "$fixture" post-checkout -- a b 1
}

test_history_holds_no_unreviewed_finding() {
  assert_contains "$REPOSITORY_ROOT/.github/workflows/ci.yml" 'gitleaks git --redact --no-banner .'
  assert_contains "$REPOSITORY_ROOT/.github/workflows/ci.yml" 'fetch-depth: 0'
  assert_equal 2 "$(grep -c '^[0-9a-f]\{40\}:' "$REPOSITORY_ROOT/.gitleaksignore")" \
    'reviewed findings'
}

scenario_run 'the default key enables signing' \
  test_the_default_key_enables_signing
scenario_run 'an explicit choice about signing is kept' \
  test_an_explicit_choice_about_signing_is_kept
scenario_run 'signing stays off without a key' \
  test_signing_stays_off_without_a_key
scenario_run 'the identity link survives the installer' \
  test_the_identity_link_survives_the_installer
scenario_run 'the installer links the hooks the configuration names' \
  test_the_installer_links_the_hooks_the_configuration_names
scenario_run 'every hook is the dispatcher' \
  test_every_hook_is_the_dispatcher
scenario_run 'a commit scans the staged changes' \
  test_a_commit_scans_the_staged_changes
scenario_run 'a finding stops the commit before the repository hook' \
  test_a_finding_stops_the_commit_before_the_repository_hook
scenario_run 'the repository hook runs with its arguments and input' \
  test_the_repository_hook_runs_with_its_arguments_and_input
scenario_run 'a missing scanner or repository hook is not an error' \
  test_a_missing_scanner_or_repository_hook_is_not_an_error
scenario_run 'history holds no unreviewed finding' \
  test_history_holds_no_unreviewed_finding

scenario_finish
