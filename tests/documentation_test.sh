#!/usr/bin/env bash

set -euo pipefail

TEST_PATH=${BASH_SOURCE[0]}
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")/.." && pwd)
README=$REPOSITORY_ROOT/README.md
AGENTS=$REPOSITORY_ROOT/AGENTS.md
CODING_STANDARDS=$REPOSITORY_ROOT/CODING_STANDARDS.md
OPENCODE_README=$REPOSITORY_ROOT/opencode/README.md
OPENCODE_ALIASES=$REPOSITORY_ROOT/opencode/aliases.zsh

# shellcheck source=tests/_support/opencode-catalog.sh
# shellcheck disable=SC1091
source "$(dirname -- "$TEST_PATH")/_support/opencode-catalog.sh"

failures=0

assert_documented_in() {
  local doc_path=$1
  local kind=$2
  local name=$3

  if ! grep -Fq -- "\`$name\`" "$doc_path"; then
    printf '%s is missing %s: %s\n' "${doc_path#"$REPOSITORY_ROOT/"}" "$kind" "$name" >&2
    failures=$((failures + 1))
  fi
}

assert_alias_defined() {
  local alias_file=$1
  local alias_name=$2

  if ! grep -Eq "^alias ${alias_name}=" "$alias_file"; then
    printf '%s is missing OpenCode profile alias: %s\n' \
      "${alias_file#"$REPOSITORY_ROOT/"}" "$alias_name" >&2
    failures=$((failures + 1))
  fi
}

if [ -e "$REPOSITORY_ROOT/GUIDELINES.md" ]; then
  printf 'GUIDELINES.md is stale; use CODING_STANDARDS.md\n' >&2
  failures=$((failures + 1))
fi

assert_documented_in "$README" 'documentation file' 'CODING_STANDARDS.md'
assert_documented_in "$AGENTS" 'documentation file' 'CODING_STANDARDS.md'

while IFS= read -r command_path; do
  assert_documented_in "$README" 'bin command' "$(basename -- "$command_path")"
done < <(find "$REPOSITORY_ROOT/bin" -mindepth 1 -maxdepth 1 -type f -print | sort)

while IFS= read -r function_path; do
  function_name=$(basename -- "$function_path")
  case "$function_name" in
    _*) continue ;;
  esac
  assert_documented_in "$README" 'public function' "$function_name"
done < <(find "$REPOSITORY_ROOT/functions" -mindepth 1 -maxdepth 1 -type f -print | sort)

topic_catalog=$("$REPOSITORY_ROOT/_scripts/topic-catalog" "$REPOSITORY_ROOT")

while IFS= read -r alias_name; do
  assert_documented_in "$README" 'shell alias' "$alias_name"
done < <(
  while IFS=$'\t' read -r catalog_kind catalog_path; do
    [ "$catalog_kind" = aliases ] || continue
    sed -n 's/^alias \([^=]*\)=.*/\1/p' "$catalog_path"
  done <<<"$topic_catalog" | sort -u
)

while IFS= read -r package_name; do
  assert_documented_in "$README" 'Brewfile dependency' "$package_name"
done < <(awk -F "'" '/^(brew|cask|mas) / { print $2 }' "$REPOSITORY_ROOT/Brewfile")

while IFS= read -r tool_name; do
  assert_documented_in "$README" 'Mise tool' "$tool_name"
done < <(
  awk -F '=' '
    /^\[tools\]$/ { in_tools = 1; next }
    /^\[/ { in_tools = 0 }
    /^[[:space:]]*#/ { next }
    in_tools {
      name = $1
      gsub(/[[:space:]\"]/, "", name)
      if (name != "") print name
    }
  ' "$REPOSITORY_ROOT/mise/config.toml"
)

# The OpenCode catalog owns the managed entry list. Every row must remain
# documented in all three guides, and every profile must keep its shell
# entrypoint, because none of them derive from the catalog at runtime.
while IFS=$'\t' read -r entry_kind entry_name _; do
  if [ "$entry_kind" = entry ] && opencode_entry_is_directory "$entry_name"; then
    documented_name=$entry_name/
  else
    documented_name=$entry_name
  fi

  assert_documented_in "$README" 'OpenCode managed entry' "$documented_name"
  assert_documented_in "$AGENTS" 'OpenCode managed entry' "$documented_name"
  assert_documented_in "$OPENCODE_README" 'OpenCode managed entry' \
    "$documented_name"

  if [ "$entry_kind" = profile ]; then
    assert_alias_defined "$OPENCODE_ALIASES" "oc:$entry_name"
  fi
done < <(opencode_catalog_rows)

# The coding standards are the canonical installer-authoring contract. They
# must list every preamble helper so topics do not recreate shared behavior.
while IFS= read -r helper_name; do
  assert_documented_in "$CODING_STANDARDS" 'preamble helper' "$helper_name"
done < <(
  sed -n 's/^\(installer_[a-z_]*\)() {$/\1/p' \
    "$REPOSITORY_ROOT/_scripts/installer-preamble.sh" | sort -u
)

if ((failures > 0)); then
  exit 1
fi

echo 'Documentation coverage tests passed.'
