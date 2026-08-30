# shellcheck shell=bash
#
# The one JSONC reader fixtures share.
#
# Tracked JSONC in this repository carries whole-line comments and nothing
# else; `//` and `/*` also appear inside strings, as URLs and file globs. So
# the conversion strips lines whose first non-blank characters are `//` and
# leaves every other line alone, which is what keeps `"**/*.pem"` intact.
#
# `yq -p json` is not an alternative: it rejects a comment outright, so a
# suite using it can only validate JSONC that happens to have none.
#
# Prints the file as JSON on stdout and fails when the result is not valid
# JSON, so a caller can use it as both a converter and a validity check.
#
# Usage: jsonc_to_json <path>
jsonc_to_json() {
  sed '/^[[:space:]]*\/\//d' "$1" | jq '.'
}
