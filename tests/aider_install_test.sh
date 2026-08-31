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

test_the_config_is_linked_from_the_checkout() {
  local fixture target
  fixture=$(installer_fixture)
  target=$(aider_target "$fixture")

  invoke_aider "$fixture"

  [ -L "$target" ] || scenario_fail 'expected the Aider config to be a symlink'
  assert_equal "$SOURCE" "$(readlink "$target")" 'link points at the checkout'
  assert_contains "$fixture/stdout.log" 'Aider config'
}

test_the_link_is_idempotent() {
  local fixture target
  fixture=$(installer_fixture)
  target=$(aider_target "$fixture")

  invoke_aider "$fixture"
  invoke_aider "$fixture"

  assert_equal "$SOURCE" "$(readlink "$target")" 'link survives a repeat run'
  assert_contains "$fixture/stdout.log" 'already linked'
}

# The topic used to clear the target with its own `rm`, so an existing file was
# destroyed without a backup. The linker's default policy keeps one.
test_an_existing_file_is_backed_up_rather_than_destroyed() {
  local fixture target
  fixture=$(installer_fixture)
  target=$(aider_target "$fixture")

  printf 'hand written\n' >"$target"

  invoke_aider "$fixture"

  [ -L "$target" ] || scenario_fail 'expected the target to be linked'
  assert_equal 'hand written' "$(cat "$target.backup")" 'existing file backed up'
}

# The source carries no __DOTFILES_ROOT__, which is why the rendering branch this
# installer used to run was unreachable. A placeholder returning to the source
# would need that branch back, so this states the assumption the topic now makes.
test_the_source_needs_no_checkout_substitution() {
  grep -q '__DOTFILES_ROOT__' "$SOURCE" \
    && scenario_fail 'the Aider source carries a placeholder but nothing renders it'
  return 0
}

scenario_run 'the config is linked from the checkout' \
  test_the_config_is_linked_from_the_checkout
scenario_run 'the link is idempotent' \
  test_the_link_is_idempotent
scenario_run 'an existing file is backed up rather than destroyed' \
  test_an_existing_file_is_backed_up_rather_than_destroyed
scenario_run 'the source needs no checkout substitution' \
  test_the_source_needs_no_checkout_substitution

scenario_finish
