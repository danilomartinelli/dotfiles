#!/usr/bin/env bash

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPOSITORY_ROOT="$(cd "$TEST_DIR/.." && pwd -P)"
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
source "$TEST_DIR/_support/stubs.sh"
scenario_init dotfiles-setup-tests
TEST_ROOT=$SCENARIO_ROOT

write_fixture_scripts() {
  local fixture
  fixture=$1

  stub_uname "$fixture/fake-bin"

  scenario_write_executable "$fixture/fake-bin/git" <<'EOF'
#!/bin/sh
printf 'git %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
case " $* " in
  *' rev-parse '*) exit "${FAIL_GIT_CHECKOUT:-0}" ;;
  *' pull '*) exit "${FAIL_GIT_PULL:-0}" ;;
esac
exit 0
EOF

  scenario_write_executable "$fixture/fake-bin/ssh-keygen" <<'EOF'
#!/bin/sh
printf 'ssh-keygen %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
exit 99
EOF

  stub_brew "$fixture/fake-bin" brew-template

  scenario_write_executable "$fixture/homebrew/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' homebrew-installer >> "$SCENARIO_EVENT_LOG"
if [ -n "${SETUP_TEST_BREW_TARGET:-}" ]; then
  cp "$SETUP_TEST_BREW_TEMPLATE" "$SETUP_TEST_BREW_TARGET"
  chmod +x "$SETUP_TEST_BREW_TARGET"
fi
exit "${FAIL_HOMEBREW_INSTALL:-0}"
EOF

  scenario_write_executable "$fixture/_macos/set-defaults.sh" <<'EOF'
#!/bin/sh
printf '%s\n' macos-defaults >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_DEFAULTS:-0}"
EOF

  scenario_write_executable "$fixture/_macos/set-hostname.sh" <<'EOF'
#!/bin/sh
printf '%s\n' hostname >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_HOSTNAME:-0}"
EOF

  scenario_write_executable "$fixture/alpha/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-alpha >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_TOPIC_ALPHA:-0}"
EOF

  scenario_write_executable "$fixture/zulu/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-zulu >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_TOPIC_ZULU:-0}"
EOF

  # Declared in PREREQUISITE_TOPICS, and alphabetically last, so its position in
  # the event log is the whole proof that run order is declared.
  scenario_write_executable "$fixture/workspace/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-workspace >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_TOPIC_WORKSPACE:-0}"
EOF

  scenario_write_executable "$fixture/_ignored/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-ignored >> "$SCENARIO_EVENT_LOG"
EOF

  scenario_write_executable "$fixture/bin/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' topic-bin >> "$SCENARIO_EVENT_LOG"
EOF

  scenario_write_executable "$fixture/fake-bin/editor" <<'EOF'
#!/bin/sh
printf 'editor %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
EOF

  scenario_write_executable "$fixture/fake-bin/open" <<'EOF'
#!/bin/sh
printf 'open %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
exit 0
EOF
}

make_fixture() {
  local brew_state
  local fixture

  brew_state=${1:-present}
  fixture=$(scenario_tmpdir fixture)
  mkdir -p \
    "$fixture/_scripts" \
    "$fixture/_macos" \
    "$fixture/alpha" \
    "$fixture/zulu" \
    "$fixture/workspace" \
    "$fixture/_ignored" \
    "$fixture/homebrew" \
    "$fixture/git" \
    "$fixture/sample" \
    "$fixture/sample/bundle.symlink" \
    "$fixture/ssh" \
    "$fixture/bin" \
    "$fixture/fake-bin" \
    "$fixture/fake-prefix/bin" \
    "$fixture/home"

  cp "$REPOSITORY_ROOT/_scripts/setup" "$fixture/_scripts/setup"
  cp "$REPOSITORY_ROOT/_scripts/bootstrap" "$fixture/_scripts/bootstrap"
  cp "$REPOSITORY_ROOT/_scripts/topic-catalog" "$fixture/_scripts/topic-catalog"
  cp "$REPOSITORY_ROOT/_scripts/adapter-checkout.sh" "$fixture/_scripts/adapter-checkout.sh"
  cp "$REPOSITORY_ROOT/_scripts/installer-preamble.sh" "$fixture/_scripts/installer-preamble.sh"
  cp "$REPOSITORY_ROOT/_scripts/link-dotfiles" "$fixture/_scripts/link-dotfiles"
  cp "$REPOSITORY_ROOT/_scripts/link-config" "$fixture/_scripts/link-config"
  cp "$REPOSITORY_ROOT/_scripts/checklist" "$fixture/_scripts/checklist"
  cp "$REPOSITORY_ROOT/_scripts/output.sh" "$fixture/_scripts/output.sh"
  cp "$REPOSITORY_ROOT/_scripts/_checklist.tsv" "$fixture/_scripts/_checklist.tsv"
  cp "$REPOSITORY_ROOT/_scripts/catalog.sh" "$fixture/_scripts/catalog.sh"
  cp "$REPOSITORY_ROOT/bin/dot" "$fixture/bin/dot"
  cp "$REPOSITORY_ROOT/bin/set-defaults" "$fixture/bin/set-defaults"
  cp "$REPOSITORY_ROOT/dotfiles-root.symlink" "$fixture/dotfiles-root.symlink"
  cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$fixture/homebrew/_availability.sh"
  cp "$REPOSITORY_ROOT/homebrew/_bundle.sh" "$fixture/homebrew/_bundle.sh"
  cp "$REPOSITORY_ROOT/homebrew/_maintenance.sh" "$fixture/homebrew/_maintenance.sh"
  cp "$REPOSITORY_ROOT/ssh/install.sh" "$fixture/ssh/install.sh"
  cp "$REPOSITORY_ROOT/ssh/config" "$fixture/ssh/config"
  cp "$REPOSITORY_ROOT/ssh/config_local.example" "$fixture/ssh/config_local.example"
  chmod +x \
    "$fixture/_scripts/setup" \
    "$fixture/_scripts/bootstrap" \
    "$fixture/_scripts/checklist" \
    "$fixture/_scripts/topic-catalog" \
    "$fixture/_scripts/link-dotfiles" \
    "$fixture/_scripts/link-config" \
    "$fixture/bin/dot" \
    "$fixture/bin/set-defaults" \
    "$fixture/dotfiles-root.symlink" \
    "$fixture/homebrew/_availability.sh" \
    "$fixture/homebrew/_bundle.sh" \
    "$fixture/homebrew/_maintenance.sh" \
    "$fixture/ssh/install.sh"

  printf '%s\n' '# local environment' >"$fixture/.localrc.example"
  printf '%s\n' '# Brewfile fixture' >"$fixture/Brewfile"
  printf '%s\n' '[user]' >"$fixture/git/gitconfig.local.symlink.example"
  printf '%s\n' '[user]' >"$fixture/git/gitconfig.local.symlink"
  printf '%s\n' 'fixture config' >"$fixture/sample/config.symlink"
  printf '%s\n' 'directory config' >"$fixture/sample/bundle.symlink/config.json"
  printf '%s\n' 'tracked conflict' >"$fixture/sample/preserved.symlink"
  printf '%s\n' 'reserved link' >"$fixture/_ignored/hidden.symlink"
  printf '%s\n' 'reserved link' >"$fixture/bin/reserved.symlink"

  write_fixture_scripts "$fixture"
  if [ "$brew_state" = present ]; then
    cp "$fixture/fake-bin/brew-template" "$fixture/fake-bin/brew"
    chmod +x "$fixture/fake-bin/brew"
  fi

  printf '%s\n' "$fixture"
}

invoke() {
  local fixture
  fixture=$1
  shift

  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    FAKE_BREW_PREFIX="$fixture/fake-prefix" \
    DOTFILES_HOMEBREW_ROOT="$fixture/platform" \
    EDITOR="$fixture/fake-bin/editor" \
    "$@"
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
  local fixture_ssh_config

  fixture=$(make_fixture)
  fixture_ssh_config=$(cd "$fixture/ssh" && pwd -P)/config
  invoke "$fixture" "$fixture/_scripts/setup" bootstrap

  assert_before "$fixture/stdout.log" 'Git identity' 'dotfile links'
  assert_before "$fixture/stdout.log" 'dotfile links' 'macOS defaults'
  assert_before "$fixture/events.log" macos-defaults hostname
  assert_before "$fixture/events.log" hostname homebrew-installer
  assert_before "$fixture/events.log" 'brew tap nikitabobko/tap' 'brew trust --tap'
  assert_before "$fixture/events.log" 'brew trust --tap' 'brew bundle --file'
  assert_before "$fixture/events.log" 'brew bundle --file' topic-workspace
  assert_before "$fixture/events.log" topic-alpha topic-zulu
  assert_count "$fixture/events.log" homebrew-installer 1
  assert_not_contains "$fixture/events.log" 'git '
  assert_not_contains "$fixture/events.log" 'brew update'
  assert_not_contains "$fixture/events.log" 'brew upgrade'
  assert_not_contains "$fixture/events.log" ssh-keygen
  assert_not_contains "$fixture/events.log" topic-ignored
  assert_not_contains "$fixture/events.log" topic-bin
  assert_contains "$fixture/stdout.log" 'setup bootstrap complete'
  [ -L "$fixture/home/.localrc" ]
  [ -L "$fixture/home/.config" ]
  [ -L "$fixture/home/.dotfiles-root" ]
  [ ! -e "$fixture/home/.hidden" ]
  [ ! -e "$fixture/home/.reserved" ]
  [ "$(readlink "$fixture/home/.ssh/config")" = "$fixture_ssh_config" ]
}

test_update_sequence_and_cwd_independence() {
  local fixture
  local fixture_ssh_config

  fixture=$(make_fixture)
  printf '%s\n' 'local conflict' >"$fixture/home/.preserved"
  fixture_ssh_config=$(cd "$fixture/ssh" && pwd -P)/config
  (
    cd "$TEST_ROOT" || exit 1
    invoke "$fixture" "$fixture/_scripts/setup" update
  )

  assert_before "$fixture/events.log" 'rev-parse --is-inside-work-tree' ' pull'
  assert_before "$fixture/stdout.log" 'checkout refresh' 'local environment'
  assert_before "$fixture/stdout.log" 'local environment' 'dotfile links'
  assert_before "$fixture/stdout.log" 'dotfile links' 'Homebrew available'
  assert_before "$fixture/events.log" ' pull' homebrew-installer
  assert_before "$fixture/events.log" homebrew-installer 'brew update'
  assert_before "$fixture/events.log" 'brew tap' 'brew update'
  assert_before "$fixture/events.log" 'brew update' 'brew upgrade'
  assert_before "$fixture/events.log" 'brew upgrade' 'brew tap nikitabobko/tap'
  assert_before "$fixture/events.log" 'brew trust --tap' 'brew bundle --file'
  assert_before "$fixture/events.log" 'brew bundle --file' topic-alpha
  assert_not_contains "$fixture/events.log" macos-defaults
  assert_not_contains "$fixture/events.log" hostname
  assert_not_contains "$fixture/stdout.log" 'Git identity'
  assert_not_contains "$fixture/events.log" ssh-keygen
  assert_not_contains "$fixture/events.log" topic-bin
  assert_contains "$fixture/stdout.log" 'setup update complete'
  [ -L "$fixture/home/.dotfiles-root" ]
  [ -L "$fixture/home/.config" ]
  [ -L "$fixture/home/.bundle" ]
  assert_contains "$fixture/home/.bundle/config.json" 'directory config'
  assert_contains "$fixture/home/.preserved" 'local conflict'
  [ ! -L "$fixture/home/.preserved" ]
  [ "$(readlink "$fixture/home/.ssh/config")" = "$fixture_ssh_config" ]
}

test_standard_modes_never_open_apps_or_launch_checklist() {
  local bootstrap_fixture
  local update_fixture

  bootstrap_fixture=$(make_fixture)
  invoke "$bootstrap_fixture" "$bootstrap_fixture/_scripts/setup" bootstrap
  assert_not_contains "$bootstrap_fixture/events.log" 'open '
  assert_not_contains "$bootstrap_fixture/stdout.log" 'Post-bootstrap checklist'
  awk '/^run_bootstrap\(\)/,/^}/' "$bootstrap_fixture/_scripts/setup" \
    >"$bootstrap_fixture/bootstrap-function.txt"
  assert_not_contains "$bootstrap_fixture/bootstrap-function.txt" open
  assert_not_contains "$bootstrap_fixture/bootstrap-function.txt" checklist

  update_fixture=$(make_fixture)
  invoke "$update_fixture" "$update_fixture/_scripts/setup" update
  assert_not_contains "$update_fixture/events.log" 'open '
  assert_not_contains "$update_fixture/stdout.log" 'Post-bootstrap checklist'
  awk '/^run_update\(\)/,/^}/' "$update_fixture/_scripts/setup" \
    >"$update_fixture/update-function.txt"
  assert_not_contains "$update_fixture/update-function.txt" open
  assert_not_contains "$update_fixture/update-function.txt" checklist
}

test_checklist_opening_requires_interactive_opt_in() {
  local fixture
  local status=0

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" checklist --open-apps || status=$?

  assert_equal 1 "$status" 'non-interactive checklist status'
  assert_contains "$fixture/stderr.log" \
    'app checklist opening requires an interactive terminal'
  assert_not_contains "$fixture/events.log" 'open '
  assert_contains "$fixture/_scripts/setup" \
    "[ \"\$#\" -eq 2 ] && [ \"\$1\" = checklist ] && [ \"\$2\" = --open-apps ]"
}

# The app column of the checklist catalog is the single owner of what gets
# opened and of which heading a row prints under, which is only true while
# neither setup nor the checklist module names an application itself.
test_setup_states_no_application_paths() {
  local fixture

  fixture=$(make_fixture)
  assert_not_contains "$fixture/_scripts/setup" '/Applications/'
  assert_not_contains "$fixture/_scripts/checklist" '/Applications/'
  assert_contains "$fixture/_scripts/checklist" 'CHECKLIST_CATALOG'
  # Setup decides when the checklist runs and nothing about what it holds.
  assert_not_contains "$fixture/_scripts/setup" 'CHECKLIST_OPEN_CANDIDATES'
}

test_checklist_catalog_rows_are_well_formed() {
  local catalog=$REPOSITORY_ROOT/_scripts/_checklist.tsv
  local kind app label note candidate

  [ -f "$catalog" ] || scenario_fail "checklist catalog not found: $catalog"

  while IFS=$'\t' read -r kind app label note || [ -n "${kind:-}" ]; do
    case "${kind:-}" in
      '' | \#*)
        kind=
        continue
        ;;
    esac

    [ -n "${app:-}" ] && [ -n "${label:-}" ] && [ -n "${note:-}" ] \
      || scenario_fail "incomplete checklist row: $kind $label"

    case "$kind" in
      credential | app | shell) ;;
      *) scenario_fail "unknown checklist kind '$kind' for $label" ;;
    esac

    if [ "$kind" != app ] && [ "$app" != - ]; then
      scenario_fail "$kind row must not declare an app: $label"
    fi

    if [ "$app" != - ]; then
      while IFS= read -r candidate; do
        case "$candidate" in
          /*.app) ;;
          *) scenario_fail "checklist candidate is not an app path: $candidate" ;;
        esac
      done <<<"${app//|/$'\n'}"
    fi
    kind=
  done <"$catalog"
}

# The roles named here are the ones git/install.sh and sops/install.sh look
# for; naming any other role tells a person to create keys those installers
# will never find.
test_checklist_names_the_key_roles_the_installers_expect() {
  local catalog=$REPOSITORY_ROOT/_scripts/_checklist.tsv

  assert_contains "$catalog" 'ssh-key-create default'
  assert_contains "$catalog" 'sops-key-create default'
  assert_contains "$REPOSITORY_ROOT/git/install.sh" 'ssh-key-create default'
  assert_contains "$REPOSITORY_ROOT/sops/install.sh" 'sops-key-create default'
}

test_app_installers_never_launch_apps_implicitly() {
  local installer

  for installer in \
    "$REPOSITORY_ROOT/bartender/install.sh" \
    "$REPOSITORY_ROOT/keyclu/install.sh" \
    "$REPOSITORY_ROOT/raycast/install.sh" \
    "$REPOSITORY_ROOT/skim/install.sh" \
    "$REPOSITORY_ROOT/tailscale/install.sh"; do
    if grep -Fq -- 'open -ga' "$installer"; then
      scenario_fail "installer launches an app implicitly: $installer"
      return 1
    fi
  done
}

test_legacy_homebrew_cleanup_precedes_upgrade() {
  local fixture

  fixture=$(make_fixture)
  export FAKE_BREW_TAPS=xo/xo
  invoke "$fixture" "$fixture/_scripts/setup" update
  unset FAKE_BREW_TAPS

  assert_contains "$fixture/events.log" 'brew untap xo/xo'
  assert_before "$fixture/events.log" 'brew untap xo/xo' 'brew update'
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
  local prefix_fixture
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

  prefix_fixture=$(make_fixture)
  export FAIL_BREW_PREFIX=1
  if invoke "$prefix_fixture" "$prefix_fixture/_scripts/setup" update; then
    return 1
  fi
  unset FAIL_BREW_PREFIX
  assert_contains "$prefix_fixture/stderr.log" 'Homebrew available'
  assert_not_contains "$prefix_fixture/events.log" 'brew update'
  assert_not_contains "$prefix_fixture/events.log" topic-alpha

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
  scenario_write_file "$fixture/git/gitconfig.local.symlink.example" <<'EOF'
[user]
  name = AUTHORNAME
  email = AUTHOREMAIL
[credential]
  helper = GIT_CREDENTIAL_HELPER
EOF

  printf '%s\n%s\n' 'Dan & Co|Ops' 'dan+test@example.com' \
    | scenario_capture "$fixture" env \
      HOME="$fixture/home" \
      PATH="$fixture/fake-bin:/usr/bin:/bin" \
      FAKE_BREW_PREFIX="$fixture/fake-prefix" \
      "$fixture/_scripts/setup" bootstrap

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

test_prerequisite_topics_run_first() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" bootstrap

  # workspace sorts last and runs first; alpha and zulu keep catalog order.
  assert_before "$fixture/events.log" topic-workspace topic-alpha
  assert_before "$fixture/events.log" topic-workspace topic-zulu
  assert_before "$fixture/events.log" topic-alpha topic-zulu
}

test_unknown_prerequisite_topic_stops_the_run() {
  local fixture

  fixture=$(make_fixture)
  rm -rf "$fixture/workspace"

  if invoke "$fixture" "$fixture/_scripts/setup" bootstrap; then
    return 1
  fi

  assert_contains "$fixture/stderr.log" \
    'declared prerequisite topic has no installer: workspace'
  assert_not_contains "$fixture/events.log" topic-alpha
  assert_not_contains "$fixture/stdout.log" 'setup bootstrap complete'
}

scenario_run 'setup rejects unknown modes' test_setup_usage
scenario_run 'declared prerequisite topics run before the remainder' \
  test_prerequisite_topics_run_first
scenario_run 'a declared prerequisite without an installer stops the run' \
  test_unknown_prerequisite_topic_stops_the_run
scenario_run 'bootstrap follows the identity-first phase sequence' test_bootstrap_sequence
scenario_run 'update follows the checkout-first sequence from any cwd' test_update_sequence_and_cwd_independence
scenario_run 'standard modes never open apps or launch the checklist' \
  test_standard_modes_never_open_apps_or_launch_checklist
scenario_run 'checklist opening requires explicit interactive opt-in' \
  test_checklist_opening_requires_interactive_opt_in
scenario_run 'app installers never launch apps implicitly' \
  test_app_installers_never_launch_apps_implicitly
scenario_run 'setup states no application paths of its own' \
  test_setup_states_no_application_paths
scenario_run 'checklist catalog rows are well formed' \
  test_checklist_catalog_rows_are_well_formed
scenario_run 'checklist names the key roles the installers expect' \
  test_checklist_names_the_key_roles_the_installers_expect
scenario_run 'legacy Homebrew cleanup precedes update and upgrade' test_legacy_homebrew_cleanup_precedes_upgrade
scenario_run 'advisory failures warn and continue' test_advisory_failures_continue
scenario_run 'critical failures stop the run' test_critical_failures_stop
scenario_run 'bootstrap creates and links an interactive Git identity' test_interactive_git_identity
scenario_run 'platform skips and fresh Homebrew discovery work' test_platform_and_fresh_homebrew
scenario_run 'public commands adapt to the canonical modes' test_command_adapters
scenario_finish
