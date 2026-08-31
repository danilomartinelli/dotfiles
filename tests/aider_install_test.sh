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
scenario_init dotfiles-aider-install-tests

SOURCE=$REPOSITORY_ROOT/aider/aider.conf.yml.symlink

invoke_aider() {
  local fixture=$1
  shift
  fixture_run "$fixture" "$@" -- "$REPOSITORY_ROOT/aider/install.sh"
}

aider_target() {
  printf '%s\n' "$1/home/.aider.conf.yml"
}

# The config is a *.symlink file, so link-dotfiles owns that target. A second
# owner here would re-decide it under a different conflict policy than the one
# `dot` chose moments earlier, so this topic must link nothing at all.
test_the_installer_links_nothing() {
  local fixture target
  fixture=$(installer_fixture)
  target=$(aider_target "$fixture")

  invoke_aider "$fixture"

  [ ! -e "$target" ] && [ ! -L "$target" ] \
    || scenario_fail 'the Aider installer created a target link-dotfiles owns'
}

# The precise regression: `dot` runs link-dotfiles with --batch skip, which is
# honoured as preserve-existing. Nothing later in the run may move that file.
test_a_preserved_file_survives_the_installer() {
  local fixture target
  fixture=$(installer_fixture)
  target=$(aider_target "$fixture")

  printf 'hand written\n' >"$target"

  invoke_aider "$fixture"

  assert_equal 'hand written' "$(cat "$target")" 'preserved file untouched'
  [ ! -e "$target.backup" ] \
    || scenario_fail 'the installer backed up a file the run chose to preserve'
}

test_the_run_reports_the_cli_state() {
  local fixture
  fixture=$(installer_fixture)

  invoke_aider "$fixture"

  assert_contains "$fixture/stdout.log" 'Aider configured'
}

# The source carries no __DOTFILES_ROOT__, which is why the rendering this
# installer used to perform was unreachable. A placeholder returning to the
# source would need rendering back — and link-dotfiles cannot do it, so it would
# have to become a real decision rather than a silent one.
test_the_source_needs_no_checkout_substitution() {
  grep -q '__DOTFILES_ROOT__' "$SOURCE" \
    && scenario_fail 'the Aider source carries a placeholder but nothing renders it'
  return 0
}

# link-dotfiles derives the target from the source name, so the two halves of
# this arrangement have to agree on what that name produces.
test_link_dotfiles_owns_the_expected_target() {
  local derived
  derived=$(basename "${SOURCE%.*}")

  assert_equal '.aider.conf.yml' ".$derived" \
    'link-dotfiles derives the target this topic deliberately leaves alone'
}

scenario_run 'the installer links nothing' \
  test_the_installer_links_nothing
scenario_run 'a preserved file survives the installer' \
  test_a_preserved_file_survives_the_installer
scenario_run 'the run reports the CLI state' \
  test_the_run_reports_the_cli_state
scenario_run 'the source needs no checkout substitution' \
  test_the_source_needs_no_checkout_substitution
scenario_run 'link-dotfiles owns the expected target' \
  test_link_dotfiles_owns_the_expected_target

scenario_finish
