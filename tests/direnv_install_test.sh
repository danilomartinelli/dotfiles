#!/usr/bin/env bash
#
# The trusted roots and the direnv configuration rendered from them.
#
# The installer renders into its own checkout, so every case runs a copy of the
# machinery inside the fixture: running the real one would rewrite the
# rendered file this checkout links on the machine.

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
scenario_init dotfiles-direnv-install-tests

make_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/checkout/direnv" "$fixture/workspace"
  cp -R "$REPOSITORY_ROOT/_scripts" "$fixture/checkout/_scripts"
  cp "$REPOSITORY_ROOT/direnv/install.sh" "$fixture/checkout/direnv/install.sh"
  printf '%s\n' "$fixture"
}

invoke_direnv() {
  local fixture=$1
  shift
  fixture_run "$fixture" WORKSPACE="$fixture/workspace" "$@" \
    -- "$fixture/checkout/direnv/install.sh"
}

rendered() {
  printf '%s\n' "$1/checkout/direnv/direnv.local.toml"
}

test_whitelist_names_every_trusted_root() {
  local fixture
  fixture=$(make_fixture)
  mkdir -p "$fixture/home/conductor"
  invoke_direnv "$fixture"

  assert_contains "$(rendered "$fixture")" "  \"$fixture/checkout\","
  assert_contains "$(rendered "$fixture")" "  \"$fixture/workspace\","
  assert_contains "$(rendered "$fixture")" "  \"$fixture/home/conductor\","
  assert_count "$(rendered "$fixture")" '  "' 3
}

test_direnv_also_loads_dotenv_files() {
  local fixture
  fixture=$(make_fixture)
  invoke_direnv "$fixture"

  assert_contains "$(rendered "$fixture")" 'load_dotenv = true'
}

test_config_is_linked_into_the_direnv_directory() {
  local fixture link
  fixture=$(make_fixture)
  invoke_direnv "$fixture"

  link=$fixture/home/.config/direnv/direnv.toml
  [ -L "$link" ] || scenario_fail "$link is not a symbolic link"
  assert_equal "$(rendered "$fixture")" "$(readlink "$link")" 'direnv.toml target'
}

# direnv compares the resolved path of an .envrc, so a root reached through a
# symbolic link has to be written resolved or nothing beneath it matches.
test_a_root_behind_a_symbolic_link_is_written_resolved() {
  local fixture
  fixture=$(make_fixture)
  mkdir -p "$fixture/elsewhere/workspace"
  ln -s "$fixture/elsewhere/workspace" "$fixture/workspace-link"
  invoke_direnv "$fixture" WORKSPACE="$fixture/workspace-link"

  assert_contains "$(rendered "$fixture")" "\"$fixture/elsewhere/workspace\""
  assert_not_contains "$(rendered "$fixture")" 'workspace-link'
}

test_a_moved_workspace_reaches_the_next_render() {
  local fixture
  fixture=$(make_fixture)
  mkdir -p "$fixture/moved"
  invoke_direnv "$fixture"
  invoke_direnv "$fixture" WORKSPACE="$fixture/moved"

  assert_contains "$(rendered "$fixture")" "\"$fixture/moved\""
  assert_not_contains "$(rendered "$fixture")" "\"$fixture/workspace\""
}

# APFS allows both characters in a path component; either one unescaped ends
# the TOML string early and direnv refuses the whole file.
test_quotes_and_backslashes_in_a_root_are_escaped() {
  local fixture odd
  fixture=$(make_fixture)
  odd="$fixture/odd \"quoted\" back\\slash"
  mkdir -p "$odd"
  invoke_direnv "$fixture" WORKSPACE="$odd"

  assert_contains "$(rendered "$fixture")" \
    "\"$fixture/odd \\\"quoted\\\" back\\\\slash\""
}

test_a_second_run_changes_nothing() {
  local fixture
  fixture=$(make_fixture)
  invoke_direnv "$fixture"
  cp "$(rendered "$fixture")" "$fixture/first.toml"
  invoke_direnv "$fixture"

  cmp -s "$fixture/first.toml" "$(rendered "$fixture")" \
    || scenario_fail 'the second render differs from the first'
  assert_contains "$fixture/stdout.log" 'direnv config already linked'
}

scenario_run 'the whitelist names every trusted root' \
  test_whitelist_names_every_trusted_root
scenario_run 'direnv also loads .env files' test_direnv_also_loads_dotenv_files
scenario_run 'the config is linked into the direnv directory' \
  test_config_is_linked_into_the_direnv_directory
scenario_run 'a root behind a symbolic link is written resolved' \
  test_a_root_behind_a_symbolic_link_is_written_resolved
scenario_run 'a moved workspace reaches the next render' \
  test_a_moved_workspace_reaches_the_next_render
scenario_run 'quotes and backslashes in a root are escaped' \
  test_quotes_and_backslashes_in_a_root_are_escaped
scenario_run 'a second run changes nothing' test_a_second_run_changes_nothing

scenario_finish
