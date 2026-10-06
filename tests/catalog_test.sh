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

# The reader delivers seven columns, wider than any catalog here declares. A
# catalog wider than the reader once needed a reader of its own, so the width
# is what keeps the rule "one reader" true rather than aspirational.
test_a_row_as_wide_as_the_reader_arrives_whole() {
  local fixture
  fixture=$(scenario_tmpdir fixture)

  printf '%s\n' \
    'alpha	one	two	-	-	six	seven' \
    'bravo	one	other	four	0.5	-	-' >"$fixture/catalog.tsv"

  invoke_reader "$fixture" "$fixture/catalog.tsv" "$echo_row_body"
  assert_contains "$fixture/stdout.log" '[alpha|one|two|-|-|six|seven]'
  assert_contains "$fixture/stdout.log" '[bravo|one|other|four|0.5|-|-]'
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

# The reason the module exists: a handler running duti or dockutil must not
# be able to swallow the rows still to be read.
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

# Run catalog_check over <catalog> with a validator named `row`, defined by
# <body>, the way a consumer does before its first effect.
invoke_check() {
  local fixture=$1
  local catalog=$2
  local body=$3

  cat >"$fixture/consumer.sh" <<EOF
#!/bin/sh
set -e
. "$READER"
$body
if catalog_check "$catalog" row; then
  printf 'valid\n'
else
  printf 'invalid %s\n' "\$?"
fi
EOF
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" "$fixture/consumer.sh"
}

test_a_catalog_without_rejections_is_valid() {
  local fixture
  fixture=$(scenario_tmpdir check-valid)

  printf '%s\n' 'alpha	one' 'bravo	two' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" 'row() { return 0; }'
  assert_contains "$fixture/stdout.log" 'valid'
  assert_not_contains "$fixture/stdout.log" 'invalid'
  assert_empty "$fixture/stderr.log"
}

# The whole point of checking first: every fault in the file is reported in one
# run, and each one names the line an editor shows, comments and blanks
# included.
test_every_rejection_names_its_line() {
  local fixture
  fixture=$(scenario_tmpdir check-lines)

  printf '%s\n' \
    '# a comment' \
    '' \
    'alpha	bad' \
    'bravo	good' \
    'charlie	bad' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" \
    "row() { [ \"\$2\" = good ] || catalog_reject \"bad \$1\"; return 0; }"
  assert_contains "$fixture/stdout.log" 'invalid 1'
  assert_contains "$fixture/stderr.log" "$fixture/catalog.tsv:3: bad alpha"
  assert_contains "$fixture/stderr.log" "$fixture/catalog.tsv:5: bad charlie"
  assert_not_contains "$fixture/stderr.log" 'bravo'
}

test_a_row_may_be_rejected_more_than_once() {
  local fixture
  fixture=$(scenario_tmpdir check-twice)

  printf '%s\n' 'alpha	one	two' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" \
    "row() { catalog_reject \"first \$2\"; catalog_reject \"second \$3\"; return 0; }"
  assert_contains "$fixture/stderr.log" "$fixture/catalog.tsv:1: first one"
  assert_contains "$fixture/stderr.log" "$fixture/catalog.tsv:1: second two"
}

test_a_duplicate_names_the_line_that_declared_it_first() {
  local fixture
  fixture=$(scenario_tmpdir check-duplicate)

  printf '%s\n' \
    'alpha	one	x' \
    'alpha	two	x' \
    'alpha	one	y' \
    'alpha	one	z' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" \
    "row() { catalog_reject_duplicate \"\$1\" \"\$2\"; return 0; }"
  assert_contains "$fixture/stdout.log" 'invalid 1'
  assert_not_contains "$fixture/stderr.log" 'catalog.tsv:2:'
  assert_contains "$fixture/stderr.log" "$fixture/catalog.tsv:3: duplicates line 1"
  assert_contains "$fixture/stderr.log" "$fixture/catalog.tsv:4: duplicates line 1"
}

# The pairs are catalog_expand's, so one declaration can feed both: what is
# accepted here is exactly what expands there.
test_only_declared_placeholders_are_accepted() {
  local fixture
  fixture=$(scenario_tmpdir check-placeholders)

  # shellcheck disable=SC2016 # Literal placeholders are the input under test.
  printf '%s\n' \
    'file://$HOME/	declared' \
    '$WORKSPACE	declared' \
    '$HOEM/Downloads	misspelt' \
    '$HOME_DIR	longer' \
    'costs $5 at $/unit	literal' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" \
    "row() { catalog_reject_undeclared \"\$1\" HOME /h WORKSPACE /w; return 0; }"
  assert_contains "$fixture/stdout.log" 'invalid 1'
  assert_not_contains "$fixture/stderr.log" 'catalog.tsv:1:'
  assert_not_contains "$fixture/stderr.log" 'catalog.tsv:2:'
  # shellcheck disable=SC2016 # The reported name is literal.
  assert_contains "$fixture/stderr.log" \
    "$fixture/catalog.tsv:3: unknown placeholder \$HOEM (expands \$HOME, \$WORKSPACE)"
  # shellcheck disable=SC2016 # The reported name is literal.
  assert_contains "$fixture/stderr.log" \
    "$fixture/catalog.tsv:4: unknown placeholder \$HOME_DIR"
  assert_not_contains "$fixture/stderr.log" 'catalog.tsv:5:'
}

test_a_catalog_that_expands_nothing_rejects_every_placeholder() {
  local fixture
  fixture=$(scenario_tmpdir check-no-placeholders)

  # shellcheck disable=SC2016 # A literal placeholder is the input under test.
  printf '%s\n' '$HOME/x	value' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" \
    "row() { catalog_reject_undeclared \"\$1\"; return 0; }"
  # shellcheck disable=SC2016 # The reported name is literal.
  assert_contains "$fixture/stderr.log" \
    "$fixture/catalog.tsv:1: unknown placeholder \$HOME (expands nothing)"
}

test_a_placeholder_name_without_a_replacement_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir check-arity)

  printf '%s\n' 'alpha	one' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" \
    "row() { catalog_reject_undeclared \"\$1\" HOME || printf 'refused\n'; return 0; }"
  assert_contains "$fixture/stdout.log" 'refused'
  assert_contains "$fixture/stderr.log" 'placeholder name has no replacement: HOME'
}

test_an_unreadable_catalog_fails_the_check() {
  local fixture
  fixture=$(scenario_tmpdir check-unreadable)

  invoke_check "$fixture" "$fixture/missing.tsv" 'row() { return 0; }'
  assert_contains "$fixture/stdout.log" 'invalid 1'
  assert_contains "$fixture/stderr.log" 'catalog: not readable'
}

test_an_undefined_validator_fails_the_check() {
  local fixture
  fixture=$(scenario_tmpdir check-undefined)

  printf '%s\n' 'alpha	one' >"$fixture/catalog.tsv"

  invoke_check "$fixture" "$fixture/catalog.tsv" 'other() { return 0; }'
  assert_contains "$fixture/stdout.log" 'invalid 1'
  assert_contains "$fixture/stderr.log" 'catalog: no such validator: row'
}

test_the_check_leaks_no_variables_on_either_exit() {
  local fixture
  fixture=$(scenario_tmpdir check-leak)

  printf '%s\n' 'alpha	one' 'alpha	one' >"$fixture/catalog.tsv"

  cat >"$fixture/consumer.sh" <<EOF
#!/bin/sh
. "$READER"
valid() { catalog_reject_undeclared "\$1" HOME /h; return 0; }
invalid() { catalog_reject_duplicate "\$1"; return 0; }
catalog_check "$fixture/catalog.tsv" valid
printf 'after valid: %s\\n' "\$(set | grep -c '^_catalog' || true)"
catalog_check "$fixture/catalog.tsv" invalid 2>/dev/null || true
printf 'after invalid: %s\\n' "\$(set | grep -c '^_catalog' || true)"
EOF
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" "$fixture/consumer.sh"

  assert_contains "$fixture/stdout.log" 'after valid: 0'
  assert_contains "$fixture/stdout.log" 'after invalid: 0'
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

# catalog.sh is sourced by every installer and by the interactive shell's
# startup, so neither exit from an expansion may leave a name behind. The
# refusal used to return before its unset.
# A caller that substitutes into JSON source text rather than into a decoded
# string JSON-escapes the checkout path first. APFS allows both `"` and `\` in a
# path component, and either spliced in raw yields a value jq refuses.
test_a_json_escaped_replacement_survives_argjson() {
  local fixture
  fixture=$(scenario_tmpdir expand-json)

  cat >"$fixture/consumer.sh" <<'CONSUMER'
#!/bin/sh
set -e
CONSUMER
  printf '. "%s"\n' "$READER" >>"$fixture/consumer.sh"
  cat >>"$fixture/consumer.sh" <<'CONSUMER'
root='/Users/a"b\c/dotfiles'
escaped=$(jq -rn --arg root "$root" '$root | tojson[1:-1]')
value=$(catalog_expand '"$DOTFILES_ROOT/bin/example-tool"' DOTFILES_ROOT "$escaped")
printf '%s' '{}' | jq -c --arg k binary --argjson value "$value" '.[$k] = $value'
CONSUMER
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" "$fixture/consumer.sh"

  assert_contains "$fixture/stdout.log" \
    '{"binary":"/Users/a\"b\\c/dotfiles/bin/example-tool"}'
}

test_expansion_leaks_no_variables_on_either_exit() {
  local fixture
  fixture=$(scenario_tmpdir expand-leak)

  cat >"$fixture/consumer.sh" <<EOF
#!/bin/sh
. "$READER"
catalog_expand 'value' HOME /home/a >/dev/null
printf 'after success: %s\\n' "\$(set | grep -c '^_catalog_expand' || true)"
catalog_expand 'value' HOME >/dev/null 2>&1 || true
printf 'after refusal: %s\\n' "\$(set | grep -c '^_catalog_expand' || true)"
EOF
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" "$fixture/consumer.sh"

  assert_contains "$fixture/stdout.log" 'after success: 0'
  assert_contains "$fixture/stdout.log" 'after refusal: 0'
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
scenario_run 'a row as wide as the reader arrives whole' \
  test_a_row_as_wide_as_the_reader_arrives_whole
scenario_run 'an overwide row packs its tail into the last column' \
  test_an_overwide_row_packs_its_tail
scenario_run 'a handler reading stdin cannot consume the rows' \
  test_a_handler_reading_stdin_cannot_consume_the_rows
scenario_run 'an unreadable catalog reports and fails' \
  test_an_unreadable_catalog_reports_and_fails
scenario_run 'the reader leaks no variables' \
  test_the_reader_leaks_no_variables

scenario_run 'a catalog without rejections is valid' \
  test_a_catalog_without_rejections_is_valid
scenario_run 'every rejection names its line' \
  test_every_rejection_names_its_line
scenario_run 'a row may be rejected more than once' \
  test_a_row_may_be_rejected_more_than_once
scenario_run 'a duplicate names the line that declared it first' \
  test_a_duplicate_names_the_line_that_declared_it_first
scenario_run 'only declared placeholders are accepted' \
  test_only_declared_placeholders_are_accepted
scenario_run 'a catalog that expands nothing rejects every placeholder' \
  test_a_catalog_that_expands_nothing_rejects_every_placeholder
scenario_run 'a placeholder name without a replacement is refused' \
  test_a_placeholder_name_without_a_replacement_is_refused
scenario_run 'an unreadable catalog fails the check' \
  test_an_unreadable_catalog_fails_the_check
scenario_run 'an undefined validator fails the check' \
  test_an_undefined_validator_fails_the_check
scenario_run 'the check leaks no variables on either exit' \
  test_the_check_leaks_no_variables_on_either_exit

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
scenario_run 'expansion leaks no variables on either exit' \
  test_expansion_leaks_no_variables_on_either_exit
scenario_run 'a JSON-escaped replacement survives argjson' \
  test_a_json_escaped_replacement_survives_argjson

scenario_finish
