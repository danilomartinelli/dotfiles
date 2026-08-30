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

# This suite deliberately does not use scenario_run. Its job is to list every
# undocumented surface in one pass, so it accumulates failures and reports them
# together; stopping at the first missing name would hide the rest and turn one
# documentation sweep into a dozen runs.
failures=0

# Print the Markdown section a heading opens, up to the next heading of the
# same or higher level. A documentation contract scoped this way cannot be
# satisfied by an unrelated mention elsewhere in the file.
doc_section() {
  local doc_path=$1
  local heading=$2
  local depth=${heading%%[! #]*}

  awk -v heading="$heading" -v stop="^#{1,${#depth}} " '
    $0 == heading { inside = 1; next }
    inside && $0 ~ stop { inside = 0 }
    inside { print }
  ' "$doc_path"
}

# With a heading, the name must appear inside that section; without one, the
# whole file owns the fact.
assert_documented_in() {
  local doc_path=$1
  local kind=$2
  local name=$3
  local heading=${4-}
  local where=${doc_path#"$REPOSITORY_ROOT/"}
  local haystack

  if [ -n "$heading" ]; then
    haystack=$(doc_section "$doc_path" "$heading")
    where="$where ($heading)"
  else
    haystack=$(cat "$doc_path")
  fi

  if ! printf '%s\n' "$haystack" | grep -Fq -- "\`$name\`"; then
    printf '%s is missing %s: %s\n' "$where" "$kind" "$name" >&2
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

  assert_documented_in "$README" 'OpenCode managed entry' "$documented_name" \
    '### OpenCode and OCX'
  assert_documented_in "$AGENTS" 'OpenCode managed entry' "$documented_name" \
    '### OpenCode and OCX'
  # The whole of opencode/README.md owns this surface, so it needs no anchor.
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

# Brewfile declares which third-party taps exist; homebrew/_bundle.sh declares
# which ones Homebrew is told to trust before `brew bundle` runs. Neither can
# derive the other — trust is not expressible in a Brewfile — so the two lists
# are held to each other here rather than by hand.
brewfile_taps=$(
  awk -F "'" '/^tap / { print $2 }' "$REPOSITORY_ROOT/Brewfile" | sort -u
)
trusted_taps=$(
  sed -n "s/^TRUSTED_TAPS='\(.*\)'$/\1/p" "$REPOSITORY_ROOT/homebrew/_bundle.sh" \
    | tr ' ' '\n' | sed '/^$/d' | sort -u
)

while IFS= read -r tap_name; do
  [ -n "$tap_name" ] || continue
  printf '%s\n' "$trusted_taps" | grep -Fqx -- "$tap_name" || {
    printf 'homebrew/_bundle.sh is missing a trusted tap declared in Brewfile: %s\n' \
      "$tap_name" >&2
    failures=$((failures + 1))
  }
done <<<"$brewfile_taps"

while IFS= read -r tap_name; do
  [ -n "$tap_name" ] || continue
  printf '%s\n' "$brewfile_taps" | grep -Fqx -- "$tap_name" || {
    printf 'homebrew/_bundle.sh trusts a tap the Brewfile does not declare: %s\n' \
      "$tap_name" >&2
    failures=$((failures + 1))
  }
done <<<"$trusted_taps"

# The catalog tables are rendered from Brewfile and mise/config.toml, so the
# grep coverage above proves a name is mentioned and this proves the row around
# it still matches what was declared.
if ! "$REPOSITORY_ROOT/_scripts/render-software-catalog" --check >/dev/null; then
  failures=$((failures + 1))
fi

# The profile payloads are rendered the same way, and until now only the
# OpenCode suite noticed a stale one. The suite that enforces the managed-entry
# ritual is where an unrendered profile edit should surface too.
if ! "$REPOSITORY_ROOT/_scripts/render-opencode-profiles" --check >/dev/null; then
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  exit 1
fi

echo 'Documentation coverage tests passed.'
