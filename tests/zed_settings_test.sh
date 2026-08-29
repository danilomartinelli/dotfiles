#!/usr/bin/env bash

set -euo pipefail

TEST_PATH=${BASH_SOURCE[0]}
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")/.." && pwd)
ZED_SETTINGS=$REPOSITORY_ROOT/zed/settings.json
ZED_KEYMAP=$REPOSITORY_ROOT/zed/keymap.json
PRETTIER_CONFIG=$REPOSITORY_ROOT/.prettierrc.json

fail() {
  printf 'Zed settings test failed: %s\n' "$1" >&2
  exit 1
}

jsonc_to_json() {
  sed '/^[[:space:]]*\/\//d' "$1" | jq '.'
}

settings_json=$(jsonc_to_json "$ZED_SETTINGS") \
  || fail 'settings.json is not valid JSONC'
keymap_json=$(jsonc_to_json "$ZED_KEYMAP") \
  || fail 'keymap.json is not valid JSONC'

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
  || fail 'formatter policy or unversioned sandbox paths are invalid'

# Zed must run the same formatters the static checks enforce. Prettier's
# Markdown output does not satisfy `mdformat --check`, so leaving it enabled
# drifts every file away from the checked-in format.
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
  || fail 'Markdown must format with mdformat and Shell Script with shfmt -i 2 -ci -bn'

jq -e 'type == "array"' >/dev/null <<<"$keymap_json" \
  || fail 'keymap.json must contain a JSONC array'

jq -e '
  .overrides
  | any(
      .files == ["*.jsonc"]
      and .options.parser == "json"
      and .options.trailingComma == "none"
    )
' "$PRETTIER_CONFIG" >/dev/null \
  || fail 'the Prettier JSONC override must disable trailing commas'

printf 'Zed settings tests passed.\n'
