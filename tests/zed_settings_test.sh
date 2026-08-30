#!/usr/bin/env bash

set -u

TEST_PATH=${BASH_SOURCE[0]}
TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/jsonc.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/jsonc.sh"
scenario_init dotfiles-zed-settings-tests
ZED_SETTINGS=$REPOSITORY_ROOT/zed/settings.json
ZED_KEYMAP=$REPOSITORY_ROOT/zed/keymap.json
PRETTIER_CONFIG=$REPOSITORY_ROOT/.prettierrc.json

# The tracked JSONC is converted once at file scope, because scenario_run runs
# each case in a subshell and a case cannot hand a variable to the next one.
# An empty conversion is what the first case reports on.
settings_json=$(jsonc_to_json "$ZED_SETTINGS" 2>/dev/null) || settings_json=''
keymap_json=$(jsonc_to_json "$ZED_KEYMAP" 2>/dev/null) || keymap_json=''

test_tracked_jsonc_parses() {
  [ -n "$settings_json" ] || scenario_fail 'settings.json is not valid JSONC'
  [ -n "$keymap_json" ] || scenario_fail 'keymap.json is not valid JSONC'
  jq -e 'type == "array"' >/dev/null <<<"$keymap_json" \
    || scenario_fail 'keymap.json must contain a JSONC array'
}

test_formatter_policy_and_sandbox_paths() {
  jq -e '
  .format_on_save == "on"
  and .tab_size == 2
  and .languages.JSON.prettier.allowed == true
  and .languages.JSONC.prettier.allowed == true
  and .agent_servers.opencode == {
    "default_config_options": { "mode": "build" },
    "type": "custom",
    "command": "mise",
    "args": [
      "exec",
      "--",
      "ocx",
      "opencode",
      "-p",
      "boost",
      "--no-rename",
      "acp"
    ]
  }
  and all(
    .agent.sandbox_permissions.write_paths[];
    (.requested | test("/npm-opencode-ai/[0-9]")) | not
  )
' >/dev/null <<<"$settings_json" \
    || scenario_fail 'formatter policy or unversioned sandbox paths are invalid'
}

# Zed must run the same formatters the static checks enforce. Prettier's
# Markdown output does not satisfy `mdformat --check`, so leaving it enabled
# drifts every file away from the checked-in format.
test_editor_runs_the_repository_formatters() {
  jq -e '
  .languages.Markdown.prettier.allowed == false
  and .languages.Markdown.formatter.external == {
    "command": "mise",
    "arguments": ["exec", "--", "mdformat", "-"]
  }
  and .languages["Shell Script"].formatter.external == {
    "command": "mise",
    "arguments": [
      "exec",
      "--",
      "shfmt",
      "--filename",
      "{buffer_path}",
      "-i",
      "2",
      "-ci",
      "-bn"
    ]
  }
' >/dev/null <<<"$settings_json" \
    || scenario_fail 'Markdown must format with mdformat and Shell Script with shfmt -i 2 -ci -bn'
}

test_prettier_jsonc_override() {
  jq -e '
  .overrides
  | any(
      .files == ["*.jsonc"]
      and .options.parser == "json"
      and .options.trailingComma == "none"
    )
' "$PRETTIER_CONFIG" >/dev/null \
    || scenario_fail 'the Prettier JSONC override must disable trailing commas'
}

scenario_run 'the tracked Zed JSONC parses' test_tracked_jsonc_parses
scenario_run 'formatter policy and sandbox paths hold' \
  test_formatter_policy_and_sandbox_paths
scenario_run 'the editor runs the repository formatters' \
  test_editor_runs_the_repository_formatters
scenario_run 'the Prettier JSONC override disables trailing commas' \
  test_prettier_jsonc_override
scenario_finish
