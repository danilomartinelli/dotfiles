#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-git-config-tests

# The tracked gitconfig resolves its includes through $HOME, so the fixture is
# a home directory with the same links bootstrap would create. Nothing here
# reads the developer's own configuration: git is told where home is and
# follows the declarations from there.
make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir git-config)
  mkdir -p "$fixture/home"

  ln -s "$REPOSITORY_ROOT/git/gitconfig.symlink" "$fixture/home/.gitconfig"
  ln -s "$REPOSITORY_ROOT/git/gitconfig.worktree.symlink" \
    "$fixture/home/.gitconfig.worktree"

  git init -q "$fixture/main"
  git -C "$fixture/main" -c user.email=fixture@example.com -c user.name=Fixture \
    commit -q --allow-empty -m 'fixture'
  git -C "$fixture/main" worktree add -q "$fixture/linked" -b linked

  printf '%s\n' "$fixture"
}

# GIT_CONFIG_GLOBAL is cleared as well as HOME: an exported value in the
# developer's shell would take precedence over the fixture's home and quietly
# read their real configuration instead.
config_in() {
  local fixture=$1
  local worktree=$2
  local key=$3

  env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM HOME="$fixture/home" \
    git -C "$fixture/$worktree" config --get "$key"
}

test_main_working_tree_keeps_the_filesystem_monitor() {
  local fixture
  fixture=$(make_fixture)

  assert_equal 'true' "$(config_in "$fixture" main core.fsmonitor)" \
    'core.fsmonitor in a main working tree'
}

# The crash this guards against is git's fsmonitor daemon segfaulting when the
# worktree it watches is deleted underneath it, which is the normal lifecycle
# of an agent worktree.
test_linked_worktree_disables_the_filesystem_monitor() {
  local fixture
  fixture=$(make_fixture)

  assert_equal 'false' "$(config_in "$fixture" linked core.fsmonitor)" \
    'core.fsmonitor in a linked worktree'
}

# Everything else in the tracked file still reaches a linked worktree; only the
# keys the conditional include names are answered differently.
test_linked_worktree_keeps_the_rest_of_the_configuration() {
  local fixture
  fixture=$(make_fixture)

  assert_equal 'histogram' "$(config_in "$fixture" linked diff.algorithm)" \
    'diff.algorithm in a linked worktree'
  assert_equal 'true' "$(config_in "$fixture" linked rerere.enabled)" \
    'rerere.enabled in a linked worktree'
}

# The bottom include is documented as having the last word. A conditional
# include placed below it would silently take that away.
test_machine_local_configuration_still_wins() {
  local fixture
  fixture=$(make_fixture)
  printf '[core]\n\tfsmonitor = true\n' >"$fixture/home/.gitconfig.local"

  assert_equal 'true' "$(config_in "$fixture" linked core.fsmonitor)" \
    'core.fsmonitor after a machine-local override'
}

scenario_run 'a main working tree keeps the filesystem monitor' test_main_working_tree_keeps_the_filesystem_monitor
scenario_run 'a linked worktree disables the filesystem monitor' test_linked_worktree_disables_the_filesystem_monitor
scenario_run 'a linked worktree keeps the rest of the configuration' test_linked_worktree_keeps_the_rest_of_the_configuration
scenario_run 'machine-local configuration still wins' test_machine_local_configuration_still_wins
scenario_finish
