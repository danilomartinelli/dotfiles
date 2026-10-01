#!/usr/bin/env bash
#
# The coding-agent topics: the shared instructions every agent reads, and the
# credential-free settings each agent topic links.

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
scenario_init dotfiles-agents-install-tests

invoke_topic() {
  local fixture=$1
  local topic=$2
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/$topic/install.sh"
}

assert_links_to() {
  local link=$1
  local source=$2

  [ -L "$link" ] || {
    scenario_fail "$link is not a symbolic link"
    return 1
  }
  assert_equal "$source" "$(readlink "$link")" "target of $link"
}

test_every_agent_reads_the_shared_instructions() {
  local fixture instructions
  fixture=$(installer_fixture)
  instructions=$REPOSITORY_ROOT/agents/instructions.md
  invoke_topic "$fixture" agents

  assert_links_to "$fixture/home/.claude/CLAUDE.md" "$instructions"
  assert_links_to "$fixture/home/.codex/AGENTS.md" "$instructions"
  assert_links_to "$fixture/home/.agents/AGENTS.md" "$instructions"
  assert_links_to "$fixture/home/.config/opencode/AGENTS.md" "$instructions"
}

test_existing_instructions_are_backed_up_once() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/home/.codex"
  printf 'hand-written\n' >"$fixture/home/.codex/AGENTS.md"
  invoke_topic "$fixture" agents

  assert_contains "$fixture/home/.codex/AGENTS.md.backup" 'hand-written'
  assert_links_to "$fixture/home/.codex/AGENTS.md" \
    "$REPOSITORY_ROOT/agents/instructions.md"
}

test_a_second_run_reports_every_link_current() {
  local fixture
  fixture=$(installer_fixture)
  invoke_topic "$fixture" agents
  invoke_topic "$fixture" agents

  assert_count "$fixture/stdout.log" 'instructions already linked' 4
}

test_each_agent_topic_links_its_settings() {
  local fixture
  fixture=$(installer_fixture)
  invoke_topic "$fixture" claude
  invoke_topic "$fixture" kimi
  invoke_topic "$fixture" conductor
  invoke_topic "$fixture" opencode

  assert_links_to "$fixture/home/.claude/settings.json" \
    "$REPOSITORY_ROOT/claude/settings.json"
  assert_links_to "$fixture/home/.kimi-code/tui.toml" \
    "$REPOSITORY_ROOT/kimi/tui.toml"
  assert_links_to "$fixture/home/.conductor/settings.toml" \
    "$REPOSITORY_ROOT/conductor/settings.toml"
  assert_links_to "$fixture/home/.config/opencode/opencode.jsonc" \
    "$REPOSITORY_ROOT/opencode/opencode.jsonc"
  assert_links_to "$fixture/home/.config/opencode/tui.jsonc" \
    "$REPOSITORY_ROOT/opencode/tui.jsonc"
}

# Kimi Code keeps provider credentials beside the file its topic links, and
# rewrites it on every login.
test_credential_files_beside_a_linked_one_are_left_alone() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/home/.kimi-code"
  printf 'api_key = "machine-local"\n' >"$fixture/home/.kimi-code/config.toml"
  invoke_topic "$fixture" kimi

  [ ! -L "$fixture/home/.kimi-code/config.toml" ] \
    || scenario_fail 'config.toml was replaced by a link'
  assert_contains "$fixture/home/.kimi-code/config.toml" 'machine-local'
}

scenario_run 'every agent reads the shared instructions' \
  test_every_agent_reads_the_shared_instructions
scenario_run 'existing instructions are backed up once' \
  test_existing_instructions_are_backed_up_once
scenario_run 'a second run reports every link current' \
  test_a_second_run_reports_every_link_current
scenario_run 'each agent topic links its settings' \
  test_each_agent_topic_links_its_settings
scenario_run 'credential files beside a linked one are left alone' \
  test_credential_files_beside_a_linked_one_are_left_alone

scenario_finish
