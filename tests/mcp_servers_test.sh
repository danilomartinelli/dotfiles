#!/usr/bin/env bash
#
# The MCP server catalog and its one consumer: what it renders into the tracked
# Zed and OpenCode files, and what it applies to Claude Code and Codex.

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
# shellcheck source=tests/_support/jsonc.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/jsonc.sh"
scenario_init dotfiles-mcp-servers-tests

TAB=$'\t'

# A checkout holding the consumer, a two-row catalog, and tracked files that
# carry a stale server and a comment. A fake claude and codex keep each server
# they are given as a file under <fixture>/state/<agent>.
new_fixture() {
  local fixture file
  fixture=$(installer_fixture)
  for file in _scripts/mcp-servers _scripts/jsonc_splice.py _scripts/catalog.sh \
    _scripts/installer-output.sh agents/_mcp-servers-rules.sh; do
    mkdir -p "$fixture/checkout/$(dirname "$file")"
    cp "$REPOSITORY_ROOT/$file" "$fixture/checkout/$file"
  done
  ln -s "$(command -v jq)" "$fixture/fake-bin/jq"
  ln -s "$(command -v python3)" "$fixture/fake-bin/python3"

  scenario_write_file "$fixture/checkout/agents/_mcp-servers.tsv" <<EOF
# name, transport, target, environment, agents
local-one${TAB}local${TAB}tool serve --mcp${TAB}TOOL_QUIET=1 TOOL_MODE=a${TAB}claude,codex,opencode,zed
remote-one${TAB}remote${TAB}https://example.invalid/mcp${TAB}-${TAB}codex,zed
EOF
  scenario_write_file "$fixture/checkout/zed/settings.json" <<'EOF'
{
  // A comment the render must keep.
  "context_servers": {
    "stale": { "enabled": true }
  },
  "theme": "kept"
}
EOF
  scenario_write_file "$fixture/checkout/opencode/opencode.jsonc" <<'EOF'
{
  "mcp": {
    // The entry outside the catalog.
    "argent": { "type": "local" },
    "servers": {
      "stale": { "type": "remote", "url": "https://stale.invalid" }
    }
  }
}
EOF

  scenario_write_executable "$fixture/fake-bin/claude" <<'EOF'
#!/bin/sh
state=$FAKE_AGENT_STATE/claude
mkdir -p "$state"
[ "$1" = mcp ] || exit 2
shift
printf 'claude %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
case $1 in
  get) [ -f "$state/$2" ] && cat "$state/$2" ;;
  list)
    printf 'plugin:posthog:posthog: https://plugin.invalid - ok\n'
    for file in "$state"/*; do
      [ -f "$file" ] && printf '%s: target - ok\n' "$(basename "$file")"
    done
    exit 0
    ;;
  remove) rm -f "$state/$4" ;;
  add)
    [ "${FAIL_CLAUDE_ADD:-0}" = 0 ] || exit "$FAIL_CLAUDE_ADD"
    if [ "$4" = --transport ]; then
      printf '%s:\n  URL: %s\n' "$6" "$7" >"$state/$6"
    else
      name=$4
      while [ "$1" != -- ]; do shift; done
      shift
      command=$1
      shift
      printf '%s:\n  Command: %s\n  Args: %s\n' "$name" "$command" "$*" >"$state/$name"
    fi
    ;;
esac
EOF
  scenario_write_executable "$fixture/fake-bin/codex" <<'EOF'
#!/bin/sh
state=$FAKE_AGENT_STATE/codex
mkdir -p "$state"
[ "$1" = mcp ] || exit 2
shift
printf 'codex %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
case $1 in
  get) [ -f "$state/$2" ] && cat "$state/$2" ;;
  list)
    printf '['
    separator=
    for file in "$state"/*; do
      [ -f "$file" ] || continue
      printf '%s{"name":"%s"}' "$separator" "$(basename "$file")"
      separator=,
    done
    printf ']\n'
    ;;
  remove) rm -f "$state/$2" ;;
  add)
    name=$2
    if [ "$3" = --url ]; then
      printf '{"transport":{"url":"%s"}}\n' "$4" >"$state/$name"
    else
      while [ "$1" != -- ]; do shift; done
      shift
      command=$1
      shift
      printf '{"transport":{"command":"%s","args":["%s","%s"]}}\n' "$command" "$1" "$2" >"$state/$name"
    fi
    ;;
esac
EOF
  printf '%s\n' "$fixture"
}

# Usage: run_consumer <fixture> [KEY=value ...] -- <operation> [option]
run_consumer() {
  local fixture=$1
  shift
  local -a overrides=()
  while [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  shift
  fixture_run "$fixture" FAKE_AGENT_STATE="$fixture/state" \
    ${overrides[@]+"${overrides[@]}"} -- "$fixture/checkout/_scripts/mcp-servers" "$@"
}

test_the_tracked_files_match_the_catalog() {
  local fixture
  fixture=$(scenario_tmpdir tracked)
  "$REPOSITORY_ROOT/_scripts/mcp-servers" render --check >"$fixture/stdout.log" 2>&1 \
    || scenario_fail "a tracked file is stale:"$'\n'"$(cat "$fixture/stdout.log")"
}

test_rendering_replaces_the_servers_and_nothing_else() {
  local fixture
  fixture=$(new_fixture)
  run_consumer "$fixture" -- render

  jsonc_to_json "$fixture/checkout/zed/settings.json" | jq -e '
    .theme == "kept"
    and .context_servers == {
      "local-one": {
        "enabled": true,
        "command": "mise",
        "args": ["exec", "--", "tool", "serve", "--mcp"],
        "env": {"TOOL_QUIET": "1", "TOOL_MODE": "a"}
      },
      "remote-one": {"enabled": true, "url": "https://example.invalid/mcp"}
    }' >/dev/null || scenario_fail 'Zed did not receive exactly its rows'
  assert_contains "$fixture/checkout/zed/settings.json" '// A comment the render must keep.'

  jsonc_to_json "$fixture/checkout/opencode/opencode.jsonc" | jq -e '
    .mcp.argent == {"type": "local"}
    and .mcp.servers == {
      "local-one": {
        "type": "local",
        "command": ["tool", "serve", "--mcp"],
        "environment": {"TOOL_QUIET": "1", "TOOL_MODE": "a"}
      }
    }' >/dev/null || scenario_fail 'OpenCode did not receive exactly its rows'
  assert_contains "$fixture/checkout/opencode/opencode.jsonc" '// The entry outside the catalog.'
}

test_a_stale_file_fails_the_check_and_is_left_alone() {
  local fixture before
  fixture=$(new_fixture)
  before=$(cat "$fixture/checkout/zed/settings.json")

  assert_fails_with_status 1 run_consumer "$fixture" -- render --check
  assert_contains "$fixture/stderr.log" 'zed/settings.json is stale'
  assert_equal "$before" "$(cat "$fixture/checkout/zed/settings.json")" 'checked file'

  run_consumer "$fixture" -- render
  run_consumer "$fixture" -- render --check
}

test_applying_adds_each_agent_its_missing_servers() {
  local fixture
  fixture=$(new_fixture)
  run_consumer "$fixture" -- apply

  assert_contains "$fixture/events.log" \
    'claude add --scope user local-one -e TOOL_QUIET=1 -e TOOL_MODE=a -- tool serve --mcp'
  assert_not_contains "$fixture/events.log" 'claude add --scope user --transport http remote-one'
  assert_contains "$fixture/events.log" \
    'codex add local-one --env TOOL_QUIET=1 --env TOOL_MODE=a -- tool serve --mcp'
  assert_contains "$fixture/events.log" 'codex add remote-one --url https://example.invalid/mcp'
}

test_applying_again_changes_nothing() {
  local fixture
  fixture=$(new_fixture)
  run_consumer "$fixture" -- apply
  run_consumer "$fixture" -- apply

  assert_not_contains "$fixture/events.log" ' add '
  assert_not_contains "$fixture/events.log" ' remove '
  assert_contains "$fixture/stdout.log" 'Codex already has remote-one'
}

test_a_changed_target_replaces_the_server() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/state/codex"
  printf '{"transport":{"url":"https://old.invalid/mcp"}}\n' >"$fixture/state/codex/remote-one"
  run_consumer "$fixture" -- apply

  assert_before "$fixture/events.log" 'codex remove remote-one' \
    'codex add remote-one --url https://example.invalid/mcp'
}

test_an_undeclared_server_is_reported_and_kept() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/state/claude"
  printf 'by-hand:\n  URL: https://hand.invalid\n' >"$fixture/state/claude/by-hand"
  run_consumer "$fixture" -- apply

  assert_contains "$fixture/stdout.log" \
    'Claude Code also has by-hand, which the catalog does not declare'
  assert_not_contains "$fixture/stdout.log" 'plugin:posthog'
  [ -f "$fixture/state/claude/by-hand" ] || scenario_fail 'the undeclared server was removed'
}

test_a_missing_agent_is_skipped_with_a_warning() {
  local fixture
  fixture=$(new_fixture)
  rm "$fixture/fake-bin/codex"
  run_consumer "$fixture" -- apply

  assert_contains "$fixture/stderr.log" 'codex is not installed'
  assert_contains "$fixture/stdout.log" 'Claude Code given local-one'
}

test_an_invalid_catalog_changes_nothing() {
  local fixture
  fixture=$(new_fixture)
  printf 'bad name\tsocket\tx\t-\tzed,emacs\n' >>"$fixture/checkout/agents/_mcp-servers.tsv"

  assert_fails_with_status 1 run_consumer "$fixture" -- apply
  assert_contains "$fixture/stderr.log" "unknown transport 'socket'"
  assert_contains "$fixture/stderr.log" "unknown agent 'emacs'"
  assert_empty "$fixture/events.log"
}

test_a_missing_member_is_an_error() {
  local fixture
  fixture=$(new_fixture)

  if printf '{}' | "$REPOSITORY_ROOT/_scripts/jsonc_splice.py" \
    "$fixture/checkout/zed/settings.json" absent.member >/dev/null 2>"$fixture/splice.log"; then
    scenario_fail 'splicing an absent member succeeded'
  fi
  assert_contains "$fixture/splice.log" 'no member absent.member'
}

scenario_run 'the tracked files match the catalog' \
  test_the_tracked_files_match_the_catalog
scenario_run 'rendering replaces the servers and nothing else' \
  test_rendering_replaces_the_servers_and_nothing_else
scenario_run 'a stale file fails the check and is left alone' \
  test_a_stale_file_fails_the_check_and_is_left_alone
scenario_run 'applying adds each agent its missing servers' \
  test_applying_adds_each_agent_its_missing_servers
scenario_run 'applying again changes nothing' \
  test_applying_again_changes_nothing
scenario_run 'a changed target replaces the server' \
  test_a_changed_target_replaces_the_server
scenario_run 'an undeclared server is reported and kept' \
  test_an_undeclared_server_is_reported_and_kept
scenario_run 'a missing agent is skipped with a warning' \
  test_a_missing_agent_is_skipped_with_a_warning
scenario_run 'an invalid catalog changes nothing' \
  test_an_invalid_catalog_changes_nothing
scenario_run 'a missing member is an error' \
  test_a_missing_member_is_an_error

scenario_finish
