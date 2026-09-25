#!/usr/bin/env bash
#
# Rendering generated tables into hand-written Markdown.
#
# Both renderers build their tables through this module. Where a table lands
# inside a hand-written file is the generated-region reader's, and
# tests/generated_region_test.sh drives that; this suite covers the shape of
# the table itself.

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-markdown-table-tests

# shellcheck source=_scripts/markdown-table.sh
# shellcheck disable=SC1091
source "$REPOSITORY_ROOT/_scripts/markdown-table.sh"

tabs() {
  local joined=$1
  shift
  local cell
  for cell in "$@"; do
    joined=$joined$'\t'$cell
  done
  printf '%s' "$joined"
}

test_a_table_pads_every_column_to_its_widest_cell() {
  local fixture out
  fixture=$(scenario_tmpdir table)
  out=$fixture/table.md

  printf '%s\n' \
    "$(tabs 'a' 'purpose one')" \
    "$(tabs 'longer-name' 'p2')" \
    | markdown_table "$(tabs 'Tool' 'Purpose')" >"$out"

  # Padding to the widest cell is what mdformat would do anyway, so rendering
  # it normalized keeps the formatter and the renderer from disagreeing.
  assert_equal '| Tool        | Purpose     |' "$(sed -n 1p "$out")" 'header row'
  assert_equal '| ----------- | ----------- |' "$(sed -n 2p "$out")" 'rule row'
  assert_equal '| a           | purpose one |' "$(sed -n 3p "$out")" 'first data row'
  assert_equal '| longer-name | p2          |' "$(sed -n 4p "$out")" 'second data row'
}

test_a_table_with_no_rows_is_still_a_table() {
  local fixture out
  fixture=$(scenario_tmpdir empty-table)
  out=$fixture/table.md

  : | markdown_table "$(tabs 'Tool' 'Purpose')" >"$out"

  assert_equal '| Tool | Purpose |' "$(sed -n 1p "$out")" 'header row'
  assert_equal '| ---- | ------- |' "$(sed -n 2p "$out")" 'rule row'
  assert_equal 2 "$(awk 'END { print NR }' "$out")" 'line count'
}

scenario_run 'a table pads every column to its widest cell' \
  test_a_table_pads_every_column_to_its_widest_cell
scenario_run 'a table with no rows is still a table' \
  test_a_table_with_no_rows_is_still_a_table
scenario_finish
