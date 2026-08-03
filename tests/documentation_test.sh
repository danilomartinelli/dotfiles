#!/usr/bin/env bash

set -euo pipefail

TEST_PATH=${BASH_SOURCE[0]}
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")/.." && pwd)
README=$REPOSITORY_ROOT/README.md

failures=0

assert_documented() {
  local kind=$1
  local name=$2

  if ! grep -Fq -- "\`$name\`" "$README"; then
    printf 'README is missing %s: %s\n' "$kind" "$name" >&2
    failures=$((failures + 1))
  fi
}

while IFS= read -r command_path; do
  assert_documented 'bin command' "$(basename -- "$command_path")"
done < <(find "$REPOSITORY_ROOT/bin" -mindepth 1 -maxdepth 1 -type f -print | sort)

while IFS= read -r function_path; do
  function_name=$(basename -- "$function_path")
  case "$function_name" in
    _*) continue ;;
  esac
  assert_documented 'public function' "$function_name"
done < <(find "$REPOSITORY_ROOT/functions" -mindepth 1 -maxdepth 1 -type f -print | sort)

topic_catalog=$("$REPOSITORY_ROOT/_scripts/topic-catalog" "$REPOSITORY_ROOT")

while IFS= read -r alias_name; do
  assert_documented 'shell alias' "$alias_name"
done < <(
  while IFS=$'\t' read -r catalog_kind catalog_path; do
    [ "$catalog_kind" = aliases ] || continue
    sed -n 's/^alias \([^=]*\)=.*/\1/p' "$catalog_path"
  done <<< "$topic_catalog" | sort -u
)

while IFS= read -r package_name; do
  assert_documented 'Brewfile dependency' "$package_name"
done < <(awk -F "'" '/^(brew|cask|mas) / { print $2 }' "$REPOSITORY_ROOT/Brewfile")

while IFS= read -r tool_name; do
  assert_documented 'Mise tool' "$tool_name"
done < <(
  awk -F '=' '
    /^\[tools\]$/ { in_tools = 1; next }
    /^\[/ { in_tools = 0 }
    in_tools {
      name = $1
      gsub(/[[:space:]\"]/, "", name)
      if (name != "") print name
    }
  ' "$REPOSITORY_ROOT/mise/mise.toml.symlink"
)

if (( failures > 0 )); then
  exit 1
fi

echo 'Documentation coverage tests passed.'
