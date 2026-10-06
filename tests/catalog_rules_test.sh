#!/usr/bin/env bash
#
# Every tracked catalog satisfies its own rules.
#
# Each consumer checks its catalog before its first effect, but on the machine
# that check runs late: the defaults apply only at bootstrap, and the Dock and
# association catalogs are run-once, so a broken row would surface on the next
# new Mac or not at all. This suite runs each catalog's rules over the tracked
# file, with no consumer and no stub, so the fault stops at the pull request.

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-catalog-rules-tests

READER=$REPOSITORY_ROOT/_scripts/catalog.sh

# Catalog, rules file, and public validator, repository-relative.
CATALOG_RULES=(
  '_macos/defaults.tsv _macos/defaults-rules.sh defaults_check_row'
  '_scripts/_checklist.tsv _scripts/checklist-rules.sh checklist_check_row'
  'archiver/_associations.tsv _scripts/file-associations-rules.sh associations_check_row'
  'dock/_layout.tsv dock/_layout-rules.sh dock_layout_check_row'
  'skim/_associations.tsv _scripts/file-associations-rules.sh associations_check_row'
  'zed/_associations.tsv _scripts/file-associations-rules.sh associations_check_row'
)

# Run <validator> from <rules> over <catalog> under `set -eu`, the way the
# consumers run.
check_catalog() {
  local fixture=$1
  local catalog=$2
  local rules=$3
  local validator=$4

  # shellcheck disable=SC2016 # The body is evaluated by the child sh process.
  scenario_capture "$fixture" sh -c \
    'set -eu; . "$1"; . "$2"; catalog_check "$3" "$4"' sh \
    "$READER" "$REPOSITORY_ROOT/$rules" "$REPOSITORY_ROOT/$catalog" "$validator"
}

test_the_tracked_catalog_satisfies_its_rules() {
  local catalog=$1
  local rules=$2
  local validator=$3
  local fixture status=0

  fixture=$(scenario_tmpdir rules)
  check_catalog "$fixture" "$catalog" "$rules" "$validator" || status=$?

  [ "$status" -eq 0 ] \
    || scenario_fail "$catalog breaks its rules:"$'\n'"$(cat "$fixture/stderr.log")"
  assert_empty "$fixture/stderr.log"
}

# A tracked catalog with nothing to declare is almost certainly an accident,
# such as a merge resolution that dropped every row; one that is meant to be
# empty should be deleted with its consumer instead.
test_the_tracked_catalog_declares_a_row() {
  local catalog=$1
  local fixture

  fixture=$(scenario_tmpdir rows)
  # shellcheck disable=SC2016 # The body is evaluated by the child sh process.
  scenario_capture "$fixture" sh -c \
    'set -eu; . "$1"; rows=0; row() { rows=$((rows + 1)); }; catalog_each_row "$2" row; printf "%s\n" "$rows"' \
    sh "$READER" "$REPOSITORY_ROOT/$catalog"

  [ "$(cat "$fixture/stdout.log")" -gt 0 ] \
    || scenario_fail "$catalog declares no rows"
}

# The table is what puts a catalog in CI, so a new catalog must not be able to
# skip it, and a renamed one must not leave a row checking nothing.
test_every_tracked_catalog_has_rules() {
  local entry catalog tracked
  local -a declared=()

  for entry in "${CATALOG_RULES[@]}"; do
    declared+=("${entry%% *}")
  done

  tracked=$(git -C "$REPOSITORY_ROOT" ls-files -- '*.tsv')
  while IFS= read -r catalog; do
    [ -n "$catalog" ] || continue
    printf '%s\n' "${declared[@]}" | grep -Fqx -- "$catalog" \
      || scenario_fail "tracked catalog has no rules in this suite: $catalog"
  done <<<"$tracked"

  for catalog in "${declared[@]}"; do
    printf '%s\n' "$tracked" | grep -Fqx -- "$catalog" \
      || scenario_fail "rules declared for an untracked catalog: $catalog"
  done
}

for entry in "${CATALOG_RULES[@]}"; do
  read -r catalog rules validator <<<"$entry"
  scenario_run "the tracked $catalog satisfies its rules" \
    test_the_tracked_catalog_satisfies_its_rules "$catalog" "$rules" "$validator"
  scenario_run "the tracked $catalog declares a row" \
    test_the_tracked_catalog_declares_a_row "$catalog"
done
scenario_run 'every tracked catalog has rules' test_every_tracked_catalog_has_rules

scenario_finish
