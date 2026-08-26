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
  and all(
    .agent.sandbox_permissions.write_paths[];
    (.requested | test("/npm-opencode-ai/[0-9]")) | not
  )
' >/dev/null <<<"$settings_json" \
  || fail 'formatter policy or unversioned sandbox paths are invalid'

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
