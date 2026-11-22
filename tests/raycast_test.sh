#!/usr/bin/env bash
#
# The Raycast script commands: which project a few typed characters open, and
# what each command asks macOS to open.

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
scenario_init dotfiles-raycast-tests

SCRIPTS=$REPOSITORY_ROOT/raycast/scripts

new_fixture() {
  local fixture project
  fixture=$(installer_fixture)
  stub_open "$fixture/fake-bin"
  for project in acme/api acme/api-gateway acme/web-app other/webhooks other/Tools; do
    mkdir -p "$fixture/projects/$project"
  done
  : >"$fixture/projects/acme/api-notes.txt"
  printf '%s\n' "$fixture"
}

# Usage: run_script <fixture> <script> [argument]
run_script() {
  local fixture=$1 script=$2
  shift 2
  fixture_run "$fixture" PROJECTS="$fixture/projects" -- "$SCRIPTS/$script" "$@"
}

# Usage: assert_finds <fixture> <query> <owner/repository>
assert_finds() {
  local found
  found=$(PROJECTS="$1/projects" bash -c '. "$1"; project_find "$2"' bash \
    "$REPOSITORY_ROOT/raycast/_project.sh" "$2") || found=
  assert_equal "$1/projects/$3" "$found" "project for '$2'"
}

test_the_closest_project_name_wins() {
  local fixture
  fixture=$(new_fixture)

  assert_finds "$fixture" api acme/api
  assert_finds "$fixture" api-g acme/api-gateway
  assert_finds "$fixture" web acme/web-app
  assert_finds "$fixture" hook other/webhooks
  assert_finds "$fixture" TOOLS other/Tools
  assert_finds "$fixture" other/ other/Tools
}

test_a_file_or_an_unmatched_name_is_not_a_project() {
  local fixture
  fixture=$(new_fixture)

  if PROJECTS="$fixture/projects" bash -c '. "$1"; project_find notes || project_find zzz' \
    bash "$REPOSITORY_ROOT/raycast/_project.sh" >/dev/null; then
    scenario_fail 'a file or an unmatched name was found as a project'
  fi
}

test_open_project_opens_the_match_in_zed() {
  local fixture
  fixture=$(new_fixture)
  run_script "$fixture" open-project.sh gate

  assert_contains "$fixture/events.log" "open -a Zed $fixture/projects/acme/api-gateway"
  assert_contains "$fixture/stdout.log" 'Opened api-gateway'
}

test_open_project_in_terminal_opens_ghostty_there() {
  local fixture
  fixture=$(new_fixture)
  run_script "$fixture" open-project-in-terminal.sh web

  assert_contains "$fixture/events.log" \
    "open -na Ghostty.app --args --working-directory=$fixture/projects/acme/web-app"
}

test_no_match_opens_nothing_and_says_so() {
  local fixture script
  fixture=$(new_fixture)

  for script in open-project.sh open-project-in-terminal.sh; do
    assert_fails_with_status 1 run_script "$fixture" "$script" zzz
    assert_contains "$fixture/stdout.log" "No project matches 'zzz'"
  done
  assert_empty "$fixture/events.log"
}

test_update_dotfiles_runs_dot_in_a_window_that_stays_open() {
  local fixture
  fixture=$(new_fixture)
  run_script "$fixture" update-dotfiles.sh

  assert_contains "$fixture/events.log" \
    "open -na Ghostty.app --args --wait-after-command=true -e $REPOSITORY_ROOT/raycast/_update"
  [ -x "$REPOSITORY_ROOT/raycast/_update" ] || scenario_fail 'raycast/_update is not executable'
  # shellcheck disable=SC2016 # The literal line the launcher must hold.
  assert_contains "$REPOSITORY_ROOT/raycast/_update" 'exec "${0:A:h:h}/bin/dot"'
}

# Raycast lists a file only when it carries this metadata and can run it.
test_every_script_is_a_runnable_script_command() {
  local script
  for script in "$SCRIPTS"/*.sh; do
    [ -x "$script" ] || scenario_fail "${script##*/} is not executable"
    assert_contains "$script" '# @raycast.schemaVersion 1'
    assert_contains "$script" '# @raycast.title '
    assert_contains "$script" '# @raycast.mode '
  done
}

scenario_run 'the closest project name wins' \
  test_the_closest_project_name_wins
scenario_run 'a file or an unmatched name is not a project' \
  test_a_file_or_an_unmatched_name_is_not_a_project
scenario_run 'Open Project opens the match in Zed' \
  test_open_project_opens_the_match_in_zed
scenario_run 'Open Project in Terminal opens Ghostty there' \
  test_open_project_in_terminal_opens_ghostty_there
scenario_run 'no match opens nothing and says so' \
  test_no_match_opens_nothing_and_says_so
scenario_run 'Update Dotfiles runs dot in a window that stays open' \
  test_update_dotfiles_runs_dot_in_a_window_that_stays_open
scenario_run 'every script is a runnable script command' \
  test_every_script_is_a_runnable_script_command

scenario_finish
