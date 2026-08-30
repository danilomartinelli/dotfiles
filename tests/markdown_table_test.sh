#!/usr/bin/env bash
#
# Rendering generated tables into hand-written Markdown.
#
# Both renderers reach this module, and both are exercised only as `--check`
# against tracked files that are already current, so the rewriting path and
# every one of its refusals ran untested. This suite drives the module itself.

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

# The handler both renderers pass in: called with the block name, prints the
# body. A name it does not know is an error, which is the contract that keeps a
# renamed marker from rendering nothing.
render_block() {
  case "$1" in
    fruit) printf '%s\n' '| rendered |' ;;
    veg) printf '%s\n' '| also rendered |' ;;
    *) return 1 ;;
  esac
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

test_prose_around_a_block_survives_the_render() {
  local fixture source out
  fixture=$(scenario_tmpdir blocks)
  source=$fixture/README.md
  out=$fixture/rendered.md

  printf '%s\n' \
    '# Heading' \
    '' \
    'Hand-written prose above.' \
    '' \
    '<!-- generated: fruit -->' \
    '' \
    '| stale content that must go |' \
    '' \
    '<!-- generated-end -->' \
    '' \
    'Hand-written prose below.' >"$source"

  markdown_render_blocks "$source" render_block >"$out"

  assert_contains "$out" 'Hand-written prose above.'
  assert_contains "$out" 'Hand-written prose below.'
  assert_contains "$out" '| rendered |'
  assert_not_contains "$out" 'stale content that must go'
  # The markers survive so the next render finds the region again.
  assert_contains "$out" '<!-- generated: fruit -->'
  assert_contains "$out" '<!-- generated-end -->'
}

test_every_block_in_a_file_is_rendered() {
  local fixture source out
  fixture=$(scenario_tmpdir many-blocks)
  source=$fixture/README.md
  out=$fixture/rendered.md

  printf '%s\n' \
    '<!-- generated: fruit -->' \
    '<!-- generated-end -->' \
    'between' \
    '<!-- generated: veg -->' \
    '<!-- generated-end -->' >"$source"

  markdown_render_blocks "$source" render_block >"$out"

  assert_contains "$out" '| rendered |'
  assert_contains "$out" '| also rendered |'
  assert_before "$out" '| rendered |' 'between'
  assert_before "$out" 'between' '| also rendered |'
}

# A file with no marked region is an error rather than a silent no-op: it means
# the markers were renamed or removed and the render would quietly do nothing.
test_a_file_with_no_marked_region_is_refused() {
  local fixture source
  fixture=$(scenario_tmpdir no-markers)
  source=$fixture/README.md

  printf '%s\n' '# Heading' 'Only prose.' >"$source"

  assert_fails_with_output 'file with no marked region' \
    'no generated blocks' markdown_render_blocks "$source" render_block
}

test_a_nested_marker_is_refused() {
  local fixture source
  fixture=$(scenario_tmpdir nested)
  source=$fixture/README.md

  printf '%s\n' \
    '<!-- generated: fruit -->' \
    '<!-- generated: veg -->' \
    '<!-- generated-end -->' >"$source"

  assert_fails_with_output 'nested marker' \
    'nested generated marker' markdown_render_blocks "$source" render_block
}

test_an_unopened_end_marker_is_refused() {
  local fixture source
  fixture=$(scenario_tmpdir orphan-end)
  source=$fixture/README.md

  printf '%s\n' \
    '<!-- generated: fruit -->' \
    '<!-- generated-end -->' \
    '<!-- generated-end -->' >"$source"

  assert_fails_with_output 'unopened end marker' \
    'generated-end without an opening marker' \
    markdown_render_blocks "$source" render_block
}

test_an_unterminated_block_is_refused() {
  local fixture source
  fixture=$(scenario_tmpdir unterminated)
  source=$fixture/README.md

  printf '%s\n' \
    '<!-- generated: fruit -->' \
    'body with no end marker' >"$source"

  assert_fails_with_output 'unterminated block' \
    'unterminated generated block: fruit' \
    markdown_render_blocks "$source" render_block
}

# Both renderers make an unknown block name fatal, so a marker naming a block
# nobody emits must stop the render rather than empty the region.
test_a_failing_handler_stops_the_render() {
  local fixture source
  fixture=$(scenario_tmpdir unknown-block)
  source=$fixture/README.md

  printf '%s\n' \
    '<!-- generated: mystery -->' \
    '<!-- generated-end -->' >"$source"

  assert_fails 'handler refusing an unknown block' \
    markdown_render_blocks "$source" render_block
}

scenario_run 'a table pads every column to its widest cell' \
  test_a_table_pads_every_column_to_its_widest_cell
scenario_run 'a table with no rows is still a table' \
  test_a_table_with_no_rows_is_still_a_table
scenario_run 'prose around a block survives the render' \
  test_prose_around_a_block_survives_the_render
scenario_run 'every block in a file is rendered' test_every_block_in_a_file_is_rendered
scenario_run 'a file with no marked region is refused' \
  test_a_file_with_no_marked_region_is_refused
scenario_run 'a nested marker is refused' test_a_nested_marker_is_refused
scenario_run 'an unopened end marker is refused' test_an_unopened_end_marker_is_refused
scenario_run 'an unterminated block is refused' test_an_unterminated_block_is_refused
scenario_run 'a failing handler stops the render' test_a_failing_handler_stops_the_render
scenario_finish
