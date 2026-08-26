#!/usr/bin/env bash

set -euo pipefail

TEST_PATH=${BASH_SOURCE[0]}
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")/.." && pwd)
README=$REPOSITORY_ROOT/README.md
AGENTS=$REPOSITORY_ROOT/AGENTS.md
CODING_STANDARDS=$REPOSITORY_ROOT/CODING_STANDARDS.md

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
