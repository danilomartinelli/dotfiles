#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-catalog-tests

READER=$REPOSITORY_ROOT/_scripts/catalog.sh

# Run a consumer that reads <catalog> through the reader. The consumer runs
# under `set -e`, the way every real one does.
invoke_reader() {
  local fixture=$1
  local catalog=$2
  local body=$3

  cat >"$fixture/consumer.sh" <<EOF
#!/bin/sh
set -e
. "$READER"
$body
catalog_each_row "$catalog" row
EOF
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" env PATH="$fixture/fake-bin:/usr/bin:/bin" \
    "$fixture/consumer.sh"
}

echo_row_body="row() { printf '[%s|%s|%s|%s|%s|%s|%s]\n' \"\$1\" \"\$2\" \"\$3\" \"\$4\" \"\$5\" \"\$6\" \"\$7\"; }"

test_comment_and_blank_rows_are_skipped() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf '%s\n' \
    '# a comment' \
    '' \
    'alpha	one	two	three' \
    '#another	comment	with	columns' \
    'bravo	four	five	six' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" "$echo_row_body"
  assert_contains "$fixture/stdout.log" '[alpha|one|two|three|||]'
  assert_contains "$fixture/stdout.log" '[bravo|four|five|six|||]'
  assert_not_contains "$fixture/stdout.log" 'comment'
}

# Three of the four readers this module replaced guarded the unterminated last
# row and one did not, so the row that a hand edit drops the newline from is
# the one worth pinning.
test_a_final_row_without_a_newline_is_delivered() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf 'alpha\tone\ttwo\tthree\nbravo\tfour\tfive\tsix' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" "$echo_row_body"
  assert_contains "$fixture/stdout.log" '[bravo|four|five|six|||]'
}

test_short_rows_pad_to_the_declared_width() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf '%s\n' 'alpha	one	two' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" "$echo_row_body"
  assert_contains "$fixture/stdout.log" '[alpha|one|two||||]'
}

# The widest catalog here is seven columns. Before the reader delivered them
# all, that catalog needed a reader of its own, so the width is what keeps the
# rule "one reader" true rather than aspirational.
test_the_widest_catalog_arrives_whole() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf '%s\n' \
    'boost	default	model	-	-	high	low' \
    'boost	plan	other	fast	0.2	-	-' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" "$echo_row_body"
  assert_contains "$fixture/stdout.log" '[boost|default|model|-|-|high|low]'
  assert_contains "$fixture/stdout.log" '[boost|plan|other|fast|0.2|-|-]'
}

# A row wider than the declared width would pack its tail into the last
# argument rather than being refused, so the failure is worth stating.
test_an_overwide_row_packs_its_tail() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf '%s\n' 'a	b	c	d	e	f	g	h' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" "$echo_row_body"
  assert_contains "$fixture/stdout.log" '[a|b|c|d|e|f|g	h]'
}

# The reason the module exists: a handler running duti, dockutil, or ocx must
# not be able to swallow the rows still to be read.
test_a_handler_reading_stdin_cannot_consume_the_rows() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/fake-bin"

  scenario_write_executable "$fixture/fake-bin/greedy" <<'EOF'
#!/bin/sh
cat >/dev/null
EOF

  printf '%s\n' \
    'alpha	one	two	three' \
    'bravo	four	five	six' \
    'charlie	seven	eight	nine' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" \
    "row() { greedy; printf '[%s]\n' \"\$1\"; }"

  assert_contains "$fixture/stdout.log" '[alpha]'
  assert_contains "$fixture/stdout.log" '[bravo]'
  assert_contains "$fixture/stdout.log" '[charlie]'
}

test_an_unreadable_catalog_reports_and_fails() {
  local fixture
  local status=0
  fixture=$(scenario_tmpdir fixture)

  invoke_reader "$fixture" "$fixture/missing.tsv" "$echo_row_body" || status=$?
  assert_equal 1 "$status" 'unreadable catalog status'
  assert_contains "$fixture/stderr.log" 'catalog: not readable'
}

test_the_reader_leaks_no_variables() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf '%s\n' 'alpha	one	two	three' >"$fixture/catalog.tsv"

  cat >"$fixture/consumer.sh" <<EOF
#!/bin/sh
set -e
. "$READER"
row() { :; }
catalog_each_row "$fixture/catalog.tsv" row
set | grep '^_catalog' || printf 'no leaks\n'
EOF
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" "$fixture/consumer.sh"
  assert_contains "$fixture/stdout.log" 'no leaks'
}

# A catalog row spells paths the way a person writes them. Which names expand is
# the catalog's own fact, so the caller names them and everything else stays a
# literal `$`.
expand_in_sh() {
  local fixture=$1
  shift
  # shellcheck disable=SC2016 # The body is evaluated by the child sh process.
  scenario_capture "$fixture" sh -c '. "$1"; shift; catalog_expand "$@"' \
    sh "$READER" "$@"
}

test_only_the_named_placeholders_expand() {
  local fixture
  fixture=$(scenario_tmpdir expand-named)

  # shellcheck disable=SC2016 # A literal placeholder is the input under test.
  expand_in_sh "$fixture" '$HOME/x $WORKSPACE $NOPE $HOME' \
    HOME /home/a WORKSPACE /work

  # shellcheck disable=SC2016 # The unexpanded name is what must survive.
  assert_contains "$fixture/stdout.log" '/home/a/x /work $NOPE /home/a'
}

test_an_unnamed_placeholder_is_left_literal() {
  local fixture
  fixture=$(scenario_tmpdir expand-literal)

  # shellcheck disable=SC2016 # A literal placeholder is the input under test.
  expand_in_sh "$fixture" 'keep $WORKSPACE and {{HOME}}' HOME /home/a

  # shellcheck disable=SC2016 # The unexpanded name is what must survive.
  assert_contains "$fixture/stdout.log" 'keep $WORKSPACE and {{HOME}}'
}

test_a_value_with_no_placeholder_is_unchanged() {
  local fixture
  fixture=$(scenario_tmpdir expand-plain)

  expand_in_sh "$fixture" 'plain value' HOME /home/a

  assert_contains "$fixture/stdout.log" 'plain value'
}

# Every replacement is passed with its name, so nothing here reads the
# environment on a caller's behalf and no expansion needs `eval`.
test_a_name_without_a_replacement_is_refused() {
  local fixture status=0
  fixture=$(scenario_tmpdir expand-arity)

  # shellcheck disable=SC2016 # A literal placeholder is the input under test.
  expand_in_sh "$fixture" '$HOME' HOME || status=$?

  assert_equal 1 "$status" 'odd argument count status'
  assert_contains "$fixture/stderr.log" 'expansion name has no replacement: HOME'
}

test_a_replacement_containing_a_dollar_is_not_rescanned() {
  local fixture
  fixture=$(scenario_tmpdir expand-rescan)

  # shellcheck disable=SC2016 # A literal placeholder is the input under test.
  expand_in_sh "$fixture" '$HOME/end' HOME '$HOME'

  # shellcheck disable=SC2016 # The unexpanded name is what must survive.
  assert_contains "$fixture/stdout.log" '$HOME/end'
}

scenario_run 'comment and blank rows are skipped' \
  test_comment_and_blank_rows_are_skipped
scenario_run 'a final row without a trailing newline is delivered' \
  test_a_final_row_without_a_newline_is_delivered
scenario_run 'short rows pad to the declared width' \
  test_short_rows_pad_to_the_declared_width
scenario_run 'the widest catalog arrives whole' \
  test_the_widest_catalog_arrives_whole
scenario_run 'an overwide row packs its tail into the last column' \
  test_an_overwide_row_packs_its_tail
scenario_run 'a handler reading stdin cannot consume the rows' \
  test_a_handler_reading_stdin_cannot_consume_the_rows
scenario_run 'an unreadable catalog reports and fails' \
  test_an_unreadable_catalog_reports_and_fails
scenario_run 'the reader leaks no variables' \
  test_the_reader_leaks_no_variables

scenario_run 'only the named placeholders expand' \
  test_only_the_named_placeholders_expand
scenario_run 'an unnamed placeholder is left literal' \
  test_an_unnamed_placeholder_is_left_literal
scenario_run 'a value with no placeholder is unchanged' \
  test_a_value_with_no_placeholder_is_unchanged
scenario_run 'a name without a replacement is refused' \
  test_a_name_without_a_replacement_is_refused
scenario_run 'a replacement containing a dollar is not rescanned' \
  test_a_replacement_containing_a_dollar_is_not_rescanned

scenario_finish
