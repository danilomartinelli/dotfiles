#!/usr/bin/env bash

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPOSITORY_ROOT="$(cd "$TEST_DIR/.." && pwd -P)"
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
scenario_init dotfiles-setup-tests
TEST_ROOT=$SCENARIO_ROOT

# Setup is the only real module in this fixture. Every module it hands a phase
# to is a stub that records what it was handed, so a case observes the run
# plan — which phases run, in what order, with which links and installers —
# without copying the modules that own each phase. What those modules then do
# is their own suites' concern. One case keeps the real classifier and linker,
# because the link sources cross that seam and both sides could drift apart.

# A stub that records "<name> <arguments>" and exits with the status held in
# its failure variable, so a case injects a failure by passing that variable.
write_recording_stub() {
  local path=$1
  local name=$2
  local failure=$3

  scenario_write_executable "$path" <<EOF
#!/bin/sh
printf '%s %s\n' $name "\$*" >>"\$SCENARIO_EVENT_LOG"
exit "\${$failure:-0}"
EOF
}

# Topic catalog rows in the classifier's shape, naming fixture paths. Each
# argument is "<kind> <path relative to the fixture>".
catalog_rows() {
  local fixture=$1
  local row

  shift
  for row in "$@"; do
    printf '%s\t%s/%s\n' "${row%% *}" "$fixture" "${row#* }"
  done
}

make_fixture() {
  local brew_state=${1:-present}
  local fixture

  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/_scripts" "$fixture/git" "$fixture/sample" \
    "$fixture/fake-bin" "$fixture/fake-prefix/bin" "$fixture/home"

  cp "$REPOSITORY_ROOT/_scripts/setup" "$fixture/_scripts/setup"
  cp "$REPOSITORY_ROOT/_scripts/output.sh" "$fixture/_scripts/output.sh"
  chmod +x "$fixture/_scripts/setup"

  stub_uname "$fixture/fake-bin"
  stub_mise "$fixture/fake-bin"
  scenario_write_executable "$fixture/fake-bin/git" <<'EOF'
#!/bin/sh
printf 'git %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
case " $* " in
  *' rev-parse '*) exit "${FAIL_GIT_CHECKOUT:-0}" ;;
  *' pull '*) exit "${FAIL_GIT_PULL:-0}" ;;
esac
exit 0
EOF

  # The classifier stub prints the tree this fixture stands for. The real
  # classifier would find the same rows, sorted the same way.
  scenario_write_executable "$fixture/_scripts/topic-catalog" <<'EOF'
#!/bin/sh
printf 'topic-catalog %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
cat "$1/classified.tsv"
EOF
  catalog_rows "$fixture" \
    'installer alpha/install.sh' \
    'installer homebrew/install.sh' \
    'installer workspace/install.sh' \
    'installer zulu/install.sh' \
    'link sample/bundle.symlink' \
    'link sample/config.symlink' \
    'topic alpha' >"$fixture/classified.tsv"

  write_recording_stub "$fixture/_scripts/link-dotfiles" link-dotfiles FAIL_LINKS
  write_recording_stub "$fixture/_scripts/checklist" checklist FAIL_CHECKLIST
  write_recording_stub "$fixture/_scripts/upgrade-software" software-upgrades \
    FAIL_SOFTWARE_UPGRADES
  write_recording_stub "$fixture/_macos/set-defaults.sh" macos-defaults FAIL_DEFAULTS
  write_recording_stub "$fixture/_macos/set-hostname.sh" hostname FAIL_HOSTNAME
  write_recording_stub "$fixture/homebrew/_maintenance.sh" homebrew-maintenance \
    FAIL_HOMEBREW_MAINTENANCE
  write_recording_stub "$fixture/homebrew/_bundle.sh" homebrew-bundle FAIL_HOMEBREW_BUNDLE
  write_recording_stub "$fixture/alpha/install.sh" topic-alpha FAIL_TOPIC_ALPHA
  write_recording_stub "$fixture/workspace/install.sh" topic-workspace FAIL_TOPIC_WORKSPACE
  write_recording_stub "$fixture/zulu/install.sh" topic-zulu FAIL_TOPIC_ZULU

  # Homebrew's installer puts brew where availability then finds it, which is
  # how a case reaches the machine that has no Homebrew yet.
  stub_brew "$fixture" brew-template
  scenario_write_executable "$fixture/homebrew/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' homebrew-installer >>"$SCENARIO_EVENT_LOG"
[ "${FAIL_HOMEBREW_INSTALL:-0}" -eq 0 ] || exit "$FAIL_HOMEBREW_INSTALL"
fixture=$(dirname "$0")/..
[ -x "$fixture/fake-prefix/bin/brew" ] \
  || cp "$fixture/brew-template" "$fixture/fake-prefix/bin/brew"
EOF
  scenario_write_executable "$fixture/homebrew/_availability.sh" <<'EOF'
#!/bin/sh
prefix=$(CDPATH='' cd -P -- "$(dirname "$0")/../fake-prefix" && pwd)
case "$1" in
  binary)
    [ -x "$prefix/bin/brew" ] && printf '%s\n' "$prefix/bin/brew"
    ;;
  prefix)
    [ "${FAIL_BREW_PREFIX:-0}" -eq 0 ] || exit "$FAIL_BREW_PREFIX"
    printf '%s\n' "$prefix"
    ;;
esac
EOF
  if [ "$brew_state" = present ]; then
    cp "$fixture/brew-template" "$fixture/fake-prefix/bin/brew"
  fi

  printf '%s\n' '# local environment' >"$fixture/.localrc.example"
  printf '%s\n' '[user]' >"$fixture/git/gitconfig.local.symlink.example"
  printf '%s\n' '[user]' >"$fixture/git/gitconfig.local.symlink"
  printf '%s\n' 'directory config' >"$fixture/sample/bundle.symlink"
  printf '%s\n' 'fixture config' >"$fixture/sample/config.symlink"

  printf '%s\n' "$fixture"
}

# The real classifier and linker, in place of their stubs.
use_real_classifier_and_linker() {
  local fixture=$1

  cp "$REPOSITORY_ROOT/_scripts/topic-catalog" "$fixture/_scripts/topic-catalog"
  cp "$REPOSITORY_ROOT/_scripts/link-dotfiles" "$fixture/_scripts/link-dotfiles"
  cp "$REPOSITORY_ROOT/_scripts/link-config" "$fixture/_scripts/link-config"
  cp "$REPOSITORY_ROOT/_scripts/installer-output.sh" "$fixture/_scripts/installer-output.sh"
  chmod +x "$fixture/_scripts/topic-catalog" "$fixture/_scripts/link-dotfiles" \
    "$fixture/_scripts/link-config"
}

# Supply the run's topic catalog from a file. The case then states which
# topics and links exist rather than building them.
declare_topic_catalog() {
  local fixture=$1

  shift
  catalog_rows "$fixture" "$@" >"$fixture/declared.tsv"
  printf '%s\n' "$fixture/declared.tsv"
}

# Leading KEY=value arguments reach setup's environment, which is how a case
# injects a failure without exporting it into the next one.
invoke() {
  local fixture=$1

  shift
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    "$@"
}

test_setup_usage() {
  local fixture

  fixture=$(make_fixture)
  assert_fails_with_status 2 invoke "$fixture" "$fixture/_scripts/setup" invalid
  assert_contains "$fixture/stderr.log" 'Usage: _scripts/setup bootstrap|update'
  assert_fails_with_status 2 invoke "$fixture" "$fixture/_scripts/setup" checklist
  assert_fails_with_status 2 \
    invoke "$fixture" "$fixture/_scripts/setup" checklist --open-apps extra
  assert_empty "$fixture/events.log"
}

test_bootstrap_sequence() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" bootstrap

  assert_before "$fixture/stdout.log" 'local environment' 'Git identity'
  assert_before "$fixture/stdout.log" 'Git identity' 'topic catalog'
  assert_before "$fixture/stdout.log" 'topic catalog' 'dotfile links'
  assert_before "$fixture/events.log" topic-catalog 'link-dotfiles -- '
  assert_before "$fixture/events.log" link-dotfiles macos-defaults
  assert_before "$fixture/events.log" macos-defaults hostname
  assert_before "$fixture/events.log" hostname homebrew-installer
  assert_before "$fixture/events.log" homebrew-installer homebrew-maintenance
  assert_before "$fixture/events.log" homebrew-maintenance homebrew-bundle
  assert_before "$fixture/events.log" homebrew-bundle topic-workspace
  assert_before "$fixture/events.log" topic-alpha topic-zulu
  assert_not_contains "$fixture/events.log" 'git '
  assert_not_contains "$fixture/events.log" 'brew update'
  assert_not_contains "$fixture/events.log" software-upgrades
  assert_contains "$fixture/stdout.log" 'setup bootstrap complete'
  assert_mode "$fixture/.localrc" 600
}

test_update_sequence_and_cwd_independence() {
  local fixture

  fixture=$(make_fixture)
  (
    cd "$TEST_ROOT" || exit 1
    invoke "$fixture" "$fixture/_scripts/setup" update
  )

  assert_before "$fixture/stdout.log" 'checkout refresh' 'local environment'
  assert_before "$fixture/stdout.log" 'local environment' 'topic catalog'
  assert_before "$fixture/stdout.log" 'topic catalog' 'dotfile links'
  assert_before "$fixture/events.log" 'rev-parse --is-inside-work-tree' ' pull'
  assert_before "$fixture/events.log" ' pull' topic-catalog
  assert_before "$fixture/events.log" topic-catalog 'link-dotfiles --batch skip -- '
  assert_before "$fixture/events.log" link-dotfiles homebrew-installer
  assert_before "$fixture/events.log" homebrew-installer homebrew-maintenance
  assert_before "$fixture/events.log" homebrew-maintenance 'brew update'
  assert_before "$fixture/events.log" 'brew update' homebrew-bundle
  assert_before "$fixture/events.log" homebrew-bundle topic-workspace
  assert_before "$fixture/events.log" topic-zulu software-upgrades
  assert_not_contains "$fixture/events.log" macos-defaults
  assert_not_contains "$fixture/events.log" hostname
  assert_not_contains "$fixture/stdout.log" 'Git identity'
  assert_contains "$fixture/stdout.log" 'setup update complete'
}

# The classifier runs once, and the links and the installers both come from
# that one reading.
test_one_topic_catalog_feeds_links_and_installers() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" update

  assert_count "$fixture/events.log" topic-catalog 1
  assert_contains "$fixture/events.log" "topic-catalog $fixture"
  assert_contains "$fixture/events.log" \
    "link-dotfiles --batch skip -- $fixture/sample/bundle.symlink $fixture/sample/config.symlink"
  assert_count "$fixture/events.log" homebrew-installer 1
  assert_count "$fixture/events.log" topic-alpha 1
  assert_count "$fixture/events.log" topic-workspace 1
  assert_count "$fixture/events.log" topic-zulu 1
}

test_the_declared_catalog_decides_what_runs_and_in_what_order() {
  local fixture catalog

  fixture=$(make_fixture)
  catalog=$(declare_topic_catalog "$fixture" \
    'installer zulu/install.sh' \
    'installer homebrew/install.sh' \
    'installer workspace/install.sh' \
    'link sample/bundle.symlink')

  invoke "$fixture" DOTFILES_TOPIC_CATALOG="$catalog" "$fixture/_scripts/setup" bootstrap

  # The declared catalog replaces the classifier rather than adding to it.
  assert_not_contains "$fixture/events.log" topic-catalog
  assert_contains "$fixture/events.log" "link-dotfiles -- $fixture/sample/bundle.symlink"
  assert_not_contains "$fixture/events.log" config.symlink
  # workspace is a prerequisite topic, so it runs first whatever place the
  # catalog gives it; zulu follows in catalog order.
  assert_before "$fixture/events.log" topic-workspace topic-zulu
  # alpha is on disk and absent from the catalog, so nothing runs it.
  assert_not_contains "$fixture/events.log" topic-alpha
  assert_contains "$fixture/stdout.log" 'setup bootstrap complete'
}

# Homebrew's installer has its own phase, before the Brewfile, so a catalog
# that lists it among the topics does not run it a second time with them.
test_a_listed_homebrew_installer_runs_once_in_its_own_phase() {
  local fixture catalog

  fixture=$(make_fixture)
  catalog=$(declare_topic_catalog "$fixture" \
    'installer workspace/install.sh' \
    'installer homebrew/install.sh' \
    'installer zulu/install.sh')

  invoke "$fixture" DOTFILES_TOPIC_CATALOG="$catalog" "$fixture/_scripts/setup" update

  assert_count "$fixture/events.log" homebrew-installer 1
  assert_before "$fixture/events.log" homebrew-installer homebrew-bundle
  assert_contains "$fixture/stdout.log" 'setup update complete'
}

test_a_catalog_without_the_homebrew_installer_stops_the_run() {
  local fixture catalog

  fixture=$(make_fixture)
  catalog=$(declare_topic_catalog "$fixture" \
    'installer workspace/install.sh' \
    'link sample/config.symlink')

  assert_fails_with_status 1 invoke "$fixture" DOTFILES_TOPIC_CATALOG="$catalog" \
    "$fixture/_scripts/setup" update

  assert_contains "$fixture/stderr.log" 'Homebrew topic has no installer: homebrew'
  assert_not_contains "$fixture/events.log" link-dotfiles
  assert_not_contains "$fixture/events.log" homebrew-installer
}

# A declared catalog decides what this run links and executes, and an exported
# value reaches a real bootstrap, so each row must have the shape the
# classifier emits for this checkout. Every row below leaves it, and each is
# refused before anything consumes the catalog.
test_a_declared_catalog_may_not_name_a_path_outside_the_checkout() {
  local fixture outsider escape row

  fixture=$(make_fixture)
  outsider=$(scenario_tmpdir outsider)
  write_recording_stub "$outsider/evil/install.sh" topic-evil FAIL_EVIL
  printf '%s\n' 'outside' >"$outsider/evil.symlink"
  escape=$fixture/../${outsider##*/}

  for row in \
    "installer"$'\t'"$outsider/evil/install.sh" \
    "installer"$'\t'"$escape/evil/install.sh" \
    "installer"$'\t'"$fixture/../install.sh" \
    "installer"$'\t'"$fixture/zulu/nested/install.sh" \
    "link"$'\t'"$outsider/evil.symlink" \
    "link"$'\t'"$escape/evil.symlink" \
    "link"$'\t'"$fixture/sample/..symlink"; do
    {
      catalog_rows "$fixture" 'installer homebrew/install.sh' 'installer workspace/install.sh'
      printf '%s\n' "$row"
    } >"$fixture/declared.tsv"

    assert_fails_with_status 1 invoke "$fixture" DOTFILES_TOPIC_CATALOG="$fixture/declared.tsv" \
      "$fixture/_scripts/setup" bootstrap
    assert_contains "$fixture/stderr.log" "outside the checkout layout: ${row#*$'\t'}"
    assert_empty "$fixture/events.log"
  done
}

test_a_declared_catalog_may_not_repeat_a_row() {
  local fixture catalog

  fixture=$(make_fixture)
  catalog=$(declare_topic_catalog "$fixture" \
    'installer homebrew/install.sh' \
    'installer workspace/install.sh' \
    'installer zulu/install.sh' \
    'installer zulu/install.sh')

  assert_fails_with_status 1 invoke "$fixture" DOTFILES_TOPIC_CATALOG="$catalog" \
    "$fixture/_scripts/setup" bootstrap

  assert_contains "$fixture/stderr.log" \
    "declared topic catalog repeats a row: $fixture/zulu/install.sh"
  assert_empty "$fixture/events.log"
}

test_an_unreadable_declared_catalog_stops_the_run() {
  local fixture

  fixture=$(make_fixture)

  assert_fails_with_status 1 invoke "$fixture" DOTFILES_TOPIC_CATALOG="$fixture/absent.tsv" \
    "$fixture/_scripts/setup" bootstrap

  assert_contains "$fixture/stderr.log" 'topic catalog not readable'
  assert_empty "$fixture/events.log"
}

test_prerequisite_topics_run_first() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" bootstrap

  # workspace sorts after alpha and runs first; alpha and zulu keep catalog
  # order.
  assert_before "$fixture/events.log" topic-workspace topic-alpha
  assert_before "$fixture/events.log" topic-workspace topic-zulu
  assert_before "$fixture/events.log" topic-alpha topic-zulu
}

# The plan is checked whole when the catalog is read, so a missing prerequisite
# stops the run before the first link rather than after the Brewfile.
test_unknown_prerequisite_topic_stops_the_run() {
  local fixture catalog

  fixture=$(make_fixture)
  catalog=$(declare_topic_catalog "$fixture" \
    'installer alpha/install.sh' \
    'installer homebrew/install.sh')

  assert_fails_with_status 1 invoke "$fixture" DOTFILES_TOPIC_CATALOG="$catalog" \
    "$fixture/_scripts/setup" bootstrap

  assert_contains "$fixture/stderr.log" \
    'declared prerequisite topic has no installer: workspace'
  assert_empty "$fixture/events.log"
  assert_not_contains "$fixture/stdout.log" 'setup bootstrap complete'
}

test_standard_modes_never_launch_the_checklist() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" bootstrap
  assert_not_contains "$fixture/events.log" checklist

  invoke "$fixture" "$fixture/_scripts/setup" update
  assert_not_contains "$fixture/events.log" checklist
}

# Setup decides only that the checklist runs. The opt-in reaches the module
# unchanged, and the module's verdict is the run's.
test_the_checklist_mode_hands_the_opt_in_to_the_checklist() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" "$fixture/_scripts/setup" checklist --open-apps
  assert_equal 'checklist --open-apps' "$(command cat "$fixture/events.log")" \
    'checklist invocation'

  assert_fails_with_status 1 invoke "$fixture" FAIL_CHECKLIST=1 \
    "$fixture/_scripts/setup" checklist --open-apps
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

test_advisory_failures_continue() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" FAIL_HOSTNAME=1 "$fixture/_scripts/setup" bootstrap
  assert_contains "$fixture/stderr.log" 'hostname normalization failed; continuing'
  assert_contains "$fixture/events.log" topic-zulu
  assert_contains "$fixture/stdout.log" 'setup bootstrap complete'

  fixture=$(make_fixture)
  invoke "$fixture" FAIL_GIT_PULL=1 FAIL_HOMEBREW_MAINTENANCE=1 FAIL_BREW_UPDATE=1 \
    FAIL_SOFTWARE_UPGRADES=1 "$fixture/_scripts/setup" update
  assert_contains "$fixture/stderr.log" 'checkout refresh failed; continuing'
  assert_contains "$fixture/stderr.log" 'Homebrew legacy cleanup failed; continuing'
  assert_contains "$fixture/stderr.log" 'Homebrew update failed; continuing'
  assert_contains "$fixture/stderr.log" 'Declared software upgrades failed; continuing'
  assert_contains "$fixture/events.log" topic-zulu
  assert_contains "$fixture/stdout.log" 'setup update complete'

  fixture=$(make_fixture)
  invoke "$fixture" FAIL_GIT_CHECKOUT=1 "$fixture/_scripts/setup" update
  assert_contains "$fixture/stderr.log" 'is not a Git checkout'
  assert_contains "$fixture/stderr.log" 'checkout refresh failed; continuing'
  assert_not_contains "$fixture/events.log" ' pull'
  assert_contains "$fixture/events.log" topic-zulu
}

test_critical_failures_stop() {
  local fixture

  fixture=$(make_fixture)
  assert_fails_with_status 1 invoke "$fixture" FAIL_LINKS=1 "$fixture/_scripts/setup" bootstrap
  assert_contains "$fixture/stderr.log" 'dotfile links'
  assert_not_contains "$fixture/events.log" macos-defaults

  fixture=$(make_fixture)
  assert_fails_with_status 1 invoke "$fixture" FAIL_DEFAULTS=1 "$fixture/_scripts/setup" bootstrap
  assert_contains "$fixture/stderr.log" 'macOS defaults'
  assert_not_contains "$fixture/events.log" homebrew-installer
  assert_not_contains "$fixture/stdout.log" 'setup bootstrap complete'

  fixture=$(make_fixture)
  assert_fails_with_status 1 \
    invoke "$fixture" FAIL_HOMEBREW_INSTALL=1 "$fixture/_scripts/setup" update
  assert_contains "$fixture/stderr.log" 'Homebrew available'
  assert_not_contains "$fixture/events.log" 'brew update'
  assert_not_contains "$fixture/events.log" topic-alpha

  fixture=$(make_fixture)
  assert_fails_with_status 1 invoke "$fixture" FAIL_BREW_PREFIX=1 "$fixture/_scripts/setup" update
  assert_contains "$fixture/stderr.log" 'Homebrew available'
  assert_not_contains "$fixture/events.log" 'brew update'
  assert_not_contains "$fixture/events.log" topic-alpha

  fixture=$(make_fixture)
  assert_fails_with_status 1 \
    invoke "$fixture" FAIL_HOMEBREW_BUNDLE=1 "$fixture/_scripts/setup" update
  assert_contains "$fixture/stderr.log" 'Brewfile dependencies'
  assert_not_contains "$fixture/events.log" topic-alpha
  assert_not_contains "$fixture/stdout.log" 'setup update complete'

  fixture=$(make_fixture)
  assert_fails_with_status 1 invoke "$fixture" FAIL_TOPIC_ALPHA=1 "$fixture/_scripts/setup" update
  assert_contains "$fixture/stderr.log" 'topic installer: alpha/install.sh'
  assert_not_contains "$fixture/events.log" topic-zulu
}

# Bootstrap writes the Git identity before it reads the topic catalog, so the
# identity it just wrote is among the links. This is the case that keeps the
# real classifier and linker: the sources leave setup and must arrive.
test_bootstrap_links_the_git_identity_it_wrote() {
  local fixture

  fixture=$(make_fixture)
  use_real_classifier_and_linker "$fixture"
  rm "$fixture/git/gitconfig.local.symlink"
  scenario_write_file "$fixture/git/gitconfig.local.symlink.example" <<'EOF'
[user]
  name = AUTHORNAME
  email = AUTHOREMAIL
[credential]
  helper = GIT_CREDENTIAL_HELPER
EOF

  printf '%s\n%s\n' 'Dan & Co|Ops' 'dan+test@example.com' \
    | invoke "$fixture" "$fixture/_scripts/setup" bootstrap

  assert_contains "$fixture/git/gitconfig.local.symlink" 'name = Dan & Co|Ops'
  assert_contains "$fixture/git/gitconfig.local.symlink" 'email = dan+test@example.com'
  assert_contains "$fixture/git/gitconfig.local.symlink" 'helper = osxkeychain'
  assert_equal "$fixture/git/gitconfig.local.symlink" \
    "$(readlink "$fixture/home/.gitconfig.local")" 'Git identity link'
  assert_equal "$fixture/sample/config.symlink" \
    "$(readlink "$fixture/home/.config")" 'topic link'
  assert_equal "$fixture/.localrc" "$(readlink "$fixture/home/.localrc")" 'localrc link'
  assert_count "$fixture/events.log" homebrew-installer 1
  assert_before "$fixture/events.log" topic-workspace topic-alpha
  assert_contains "$fixture/stdout.log" 'setup bootstrap complete'
}

test_platform_and_fresh_homebrew() {
  local fixture

  fixture=$(make_fixture)
  invoke "$fixture" FAKE_UNAME=Linux "$fixture/_scripts/setup" bootstrap
  assert_not_contains "$fixture/events.log" macos-defaults
  assert_not_contains "$fixture/events.log" hostname
  assert_contains "$fixture/stdout.log" 'macOS configuration skipped on this platform'

  fixture=$(make_fixture absent)
  invoke "$fixture" "$fixture/_scripts/setup" update
  [ -x "$fixture/fake-prefix/bin/brew" ] \
    || scenario_fail 'the Homebrew installer did not provide brew'
  assert_count "$fixture/events.log" homebrew-installer 1
  assert_before "$fixture/events.log" homebrew-installer 'brew update'
  assert_contains "$fixture/events.log" homebrew-bundle
}

scenario_run 'setup rejects unknown modes' test_setup_usage
scenario_run 'bootstrap follows the identity-first phase sequence' test_bootstrap_sequence
scenario_run 'update follows the checkout-first sequence from any cwd' \
  test_update_sequence_and_cwd_independence
scenario_run 'one topic catalog feeds the links and the installers' \
  test_one_topic_catalog_feeds_links_and_installers
scenario_run 'the declared catalog decides what runs and in what order' \
  test_the_declared_catalog_decides_what_runs_and_in_what_order
scenario_run 'a listed Homebrew installer runs once, in its own phase' \
  test_a_listed_homebrew_installer_runs_once_in_its_own_phase
scenario_run 'a catalog without the Homebrew installer stops the run' \
  test_a_catalog_without_the_homebrew_installer_stops_the_run
scenario_run 'a declared catalog may not name a path outside the checkout' \
  test_a_declared_catalog_may_not_name_a_path_outside_the_checkout
scenario_run 'a declared catalog may not repeat a row' \
  test_a_declared_catalog_may_not_repeat_a_row
scenario_run 'an unreadable declared catalog stops the run' \
  test_an_unreadable_declared_catalog_stops_the_run
scenario_run 'declared prerequisite topics run before the remainder' \
  test_prerequisite_topics_run_first
scenario_run 'a declared prerequisite without an installer stops the run' \
  test_unknown_prerequisite_topic_stops_the_run
scenario_run 'standard modes never launch the checklist' \
  test_standard_modes_never_launch_the_checklist
scenario_run 'the checklist mode hands the opt-in to the checklist' \
  test_the_checklist_mode_hands_the_opt_in_to_the_checklist
scenario_run 'app installers never launch apps implicitly' \
  test_app_installers_never_launch_apps_implicitly
scenario_run 'advisory failures warn and continue' test_advisory_failures_continue
scenario_run 'critical failures stop the run' test_critical_failures_stop
scenario_run 'bootstrap links the Git identity it wrote' \
  test_bootstrap_links_the_git_identity_it_wrote
scenario_run 'platform skips and fresh Homebrew discovery work' test_platform_and_fresh_homebrew
scenario_finish
