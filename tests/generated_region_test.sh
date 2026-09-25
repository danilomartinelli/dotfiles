#!/usr/bin/env bash
#
# Generated regions inside hand-authored files.
#
# Markdown and JSONC share one reader, so every structural guarantee here runs
# against both formats through the same entrypoint, with a real source file
# and a small handler. What differs between the formats — marker spelling,
# where indentation is accepted, and the padding around a body — is asserted
# as exact bytes, because a comparison through command substitution would
# strip the very newlines several of these cases are about.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-generated-region-tests

# shellcheck source=_scripts/generated-region.sh
# shellcheck disable=SC1091
source "$REPOSITORY_ROOT/_scripts/generated-region.sh"

FORMATS=(markdown jsonc)

# The fixture's content handler. Like each renderer's, it alone decides which
# names exist, and it records every call so a case can count them.
render_fixture_region() {
  printf '%s\n' "$1" >>"$SCENARIO_EVENT_LOG"
  case "$1" in
    fruit) printf '%s\n' '| apple |' ;;
    veg) printf '%s\n' '| leek |' '| kale |' ;;
    empty) ;;
    partial)
      printf '%s\n' '| half |'
      return 1
      ;;
    *)
      printf 'fixture: unknown region: %s\n' "$1" >&2
      return 1
      ;;
  esac
}

# Accepts every name and prints it bracketed, so a case can see exactly which
# name reached the handler, whitespace included.
echo_region_name() {
  printf '%s\n' "$1" >>"$SCENARIO_EVENT_LOG"
  printf '[%s]\n' "$1"
}

# One marker line, newline included. Indentation is a parameter so that the
# cases can offer it to both formats and see which one accepts it.
opening() {
  case "$1" in
    markdown) printf '%s<!-- generated: %s -->\n' "${3-}" "$2" ;;
    jsonc) printf '%s// generated: %s\n' "${3-}" "$2" ;;
  esac
}

closing() {
  case "$1" in
    markdown) printf '%s<!-- generated-end -->\n' "${2-}" ;;
    jsonc) printf '%s// generated-end\n' "${2-}" ;;
  esac
}

# Markdown sets a body off with a blank line on each side, which is where
# mdformat puts them; JSONC adds nothing.
padding() {
  case "$1" in
    markdown) printf '\n' ;;
    jsonc) ;;
  esac
}

# A region as it sits in a source: markers around an interior the render must
# discard.
stale_region() {
  opening "$1" "$2"
  printf '%s\n' '| stale |' 'stale interior'
  closing "$1"
}

# A region as it must come out: the same markers around the handler's body.
# Usage: rendered_region <format> <name> [body-line...]
rendered_region() {
  local format=$1 name=$2
  shift 2

  opening "$format" "$name"
  padding "$format"
  [ "$#" -eq 0 ] || printf '%s\n' "$@"
  padding "$format"
  closing "$format"
}

# Render <source> through the public entrypoint into <result-dir>, setting
# RENDER_STATUS. The reader never writes the file it reads, so every render
# also proves the source is byte-for-byte what it was.
# Usage: render_source <result-dir> <format> <source> [handler]
render_source() {
  local result_dir=$1 format=$2 source=$3
  local handler=${4:-render_fixture_region}

  mkdir -p -- "$result_dir"
  cp -- "$source" "$result_dir/source.before"
  RENDER_STATUS=0
  scenario_capture "$result_dir" \
    generated_regions_render "$format" "$source" "$handler" \
    || RENDER_STATUS=$?
  cmp -s -- "$result_dir/source.before" "$source" \
    || scenario_fail "the render modified its source: $source"
}

assert_rendered() {
  local result_dir=$1 expected=$2

  assert_equal 0 "$RENDER_STATUS" 'render status'
  assert_empty "$result_dir/stderr.log"
  if ! cmp -s -- "$expected" "$result_dir/stdout.log"; then
    diff -u -- "$expected" "$result_dir/stdout.log" >&2 || true
    scenario_fail 'rendered bytes differ from the expected file'
  fi
}

# A refusal is status 1 with its reason on stderr, and none of that reason on
# stdout, where it would land inside the generated document.
assert_refused() {
  local result_dir=$1

  assert_equal 1 "$RENDER_STATUS" 'render status'
  [ -s "$result_dir/stderr.log" ] \
    || scenario_fail 'a refused render needs a diagnostic on stderr'
  grep -v '^$' "$result_dir/stderr.log" >"$result_dir/diagnostics" || true
  if [ -s "$result_dir/diagnostics" ] \
    && grep -Fxqf "$result_dir/diagnostics" "$result_dir/stdout.log"; then
    scenario_fail 'a diagnostic reached stdout'
  fi
}

# The handler's calls, in order. No names means it was never called.
assert_handler_calls() {
  local result_dir=$1
  shift

  if [ "$#" -eq 0 ]; then
    assert_empty "$result_dir/events.log"
    return
  fi
  printf '%s\n' "$@" >"$result_dir/calls.expected"
  cmp -s -- "$result_dir/calls.expected" "$result_dir/events.log" \
    || scenario_fail "handler calls were: $(tr '\n' ' ' <"$result_dir/events.log")"
}

test_one_region_is_replaced_and_everything_around_it_kept() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir one-region)

  {
    printf '%s\n' 'Manual text before.' '' '  indented manual line'
    stale_region "$format" fruit
    printf '%s\n' '' 'Manual text after.'
  } >"$fixture/source"
  {
    printf '%s\n' 'Manual text before.' '' '  indented manual line'
    rendered_region "$format" fruit '| apple |'
    printf '%s\n' '' 'Manual text after.'
  } >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit
}

test_every_region_is_rendered_in_file_order() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir many-regions)

  {
    printf '%s\n' 'before'
    stale_region "$format" fruit
    printf '%s\n' 'between'
    stale_region "$format" veg
    printf '%s\n' 'after'
  } >"$fixture/source"
  {
    printf '%s\n' 'before'
    rendered_region "$format" fruit '| apple |'
    printf '%s\n' 'between'
    rendered_region "$format" veg '| leek |' '| kale |'
    printf '%s\n' 'after'
  } >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit veg
}

test_a_repeated_name_calls_the_handler_once_per_occurrence() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir repeated)

  {
    stale_region "$format" fruit
    stale_region "$format" veg
    printf '%s\n' 'between'
    stale_region "$format" fruit
  } >"$fixture/source"
  {
    rendered_region "$format" fruit '| apple |'
    rendered_region "$format" veg '| leek |' '| kale |'
    printf '%s\n' 'between'
    rendered_region "$format" fruit '| apple |'
  } >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit veg fruit
}

test_an_empty_body_from_a_successful_handler_is_rendered() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir empty-body)

  stale_region "$format" empty >"$fixture/source"
  rendered_region "$format" empty >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" empty
}

# The reader used to read the file a line at a time and drop whatever followed
# the last newline, so the render deleted hand-written text.
test_a_final_manual_line_without_a_newline_is_kept() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir final-line)

  {
    stale_region "$format" fruit
    printf '%s' 'last manual line'
  } >"$fixture/source"
  {
    rendered_region "$format" fruit '| apple |'
    printf '%s' 'last manual line'
  } >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
}

test_a_closing_marker_at_the_end_keeps_its_missing_newline() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir final-marker)

  {
    printf '%s\n' 'before'
    opening "$format" fruit
    printf '%s\n' '| stale |'
    printf '%s' "$(closing "$format")"
  } >"$fixture/source"
  {
    printf '%s\n' 'before'
    opening "$format" fruit
    padding "$format"
    printf '%s\n' '| apple |'
    padding "$format"
    printf '%s' "$(closing "$format")"
  } >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
}

test_rendering_its_own_output_changes_nothing() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir idempotent)

  {
    printf '%s\n' 'before'
    stale_region "$format" fruit
    printf '%s\n' 'between'
    stale_region "$format" empty
    printf '%s' 'after'
  } >"$fixture/source"

  render_source "$fixture/first" "$format" "$fixture/source"
  assert_equal 0 "$RENDER_STATUS" 'first render status'
  cp "$fixture/first/stdout.log" "$fixture/rendered"

  render_source "$fixture/second" "$format" "$fixture/rendered"

  assert_rendered "$fixture/second" "$fixture/rendered"
}

test_a_file_without_markers_is_refused() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir no-markers)

  case "$format" in
    markdown) printf '%s\n' '# Heading' '' 'Only prose.' >"$fixture/source" ;;
    jsonc) printf '%s\n' '{' '  "key": true' '}' >"$fixture/source" ;;
  esac

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

test_an_empty_file_is_refused() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir empty-file)

  : >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

# Both readers first searched the file for the marker's prefix and took a hit
# as proof a region existed, so a mention in prose — or a Markdown marker that
# is indented and therefore not one — rendered nothing and reported success.
test_marker_mentions_in_ordinary_text_are_not_a_region() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir mentions)

  case "$format" in
    markdown)
      printf '%s\n' \
        'A region opens with <!-- generated: fruit --> on a line of its own.' \
        '  <!-- generated: fruit -->' \
        '  <!-- generated-end -->' >"$fixture/source"
      ;;
    jsonc)
      printf '%s\n' \
        '{' \
        '  "note": "a region opens with // generated: fruit",' \
        '  "key": true // generated: fruit' \
        '}' >"$fixture/source"
      ;;
  esac

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

test_an_empty_region_name_is_refused() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir empty-name)

  {
    printf '%s\n' 'before'
    opening "$format" ''
    printf '%s\n' '| stale |'
    closing "$format"
  } >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

test_a_nested_opening_is_refused() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir nested)

  {
    opening "$format" fruit
    opening "$format" veg
    closing "$format"
    closing "$format"
  } >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
}

test_a_closing_marker_without_an_opening_is_refused() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir orphan)

  {
    stale_region "$format" fruit
    printf '%s\n' 'between'
    closing "$format"
  } >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
}

test_a_region_without_a_closing_marker_is_refused() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir unterminated)

  {
    stale_region "$format" fruit
    opening "$format" veg
    printf '%s\n' 'the rest of the file'
  } >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"
  assert_refused "$fixture/result"

  printf '%s' "$(opening "$format" fruit)" >"$fixture/source"

  render_source "$fixture/last-line" "$format" "$fixture/source"
  assert_refused "$fixture/last-line"
}

# A marker that is almost one is text, including in the closing position:
# accepting it there would widen the syntax the reader treats as structure.
test_a_closing_marker_with_unsupported_whitespace_does_not_close() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir closing-whitespace)

  {
    opening "$format" fruit
    printf '%s \n' "$(closing "$format")"
  } >"$fixture/source"

  render_source "$fixture/trailing" "$format" "$fixture/source"
  assert_refused "$fixture/trailing"

  if [ "$format" = markdown ]; then
    {
      opening "$format" fruit
      closing "$format" '  '
    } >"$fixture/source"

    render_source "$fixture/indented" "$format" "$fixture/source"
    assert_refused "$fixture/indented"
  fi
}

test_a_name_the_handler_refuses_fails_the_render() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir unknown-name)

  stale_region "$format" mystery >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
  assert_contains "$fixture/result/stderr.log" 'fixture: unknown region: mystery'
  assert_handler_calls "$fixture/result" mystery
}

test_a_handler_failure_after_part_of_its_body_fails_the_render() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir partial-body)

  stale_region "$format" partial >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
}

test_a_handler_failure_stops_the_render_before_later_regions() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir stops)

  {
    stale_region "$format" fruit
    stale_region "$format" mystery
    stale_region "$format" veg
  } >"$fixture/source"

  render_source "$fixture/result" "$format" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result" fruit mystery
}

test_an_unreadable_source_is_a_render_failure() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir unreadable)
  mkdir "$fixture/directory"

  RENDER_STATUS=0
  scenario_capture "$fixture/missing" generated_regions_render \
    "$format" "$fixture/absent" render_fixture_region || RENDER_STATUS=$?
  assert_refused "$fixture/missing"
  assert_handler_calls "$fixture/missing"

  RENDER_STATUS=0
  scenario_capture "$fixture/not-a-file" generated_regions_render \
    "$format" "$fixture/directory" render_fixture_region || RENDER_STATUS=$?
  assert_refused "$fixture/not-a-file"
  assert_handler_calls "$fixture/not-a-file"

  # A file that exists but cannot be read is as unavailable as an absent one.
  stale_region "$format" fruit >"$fixture/sealed"
  chmod 000 "$fixture/sealed"
  RENDER_STATUS=0
  scenario_capture "$fixture/unreadable" generated_regions_render \
    "$format" "$fixture/sealed" render_fixture_region || RENDER_STATUS=$?
  chmod 600 "$fixture/sealed"
  assert_refused "$fixture/unreadable"
  assert_handler_calls "$fixture/unreadable"
}

# Names reach the handler exactly as written between the marker's fixed parts.
# The handler then refuses a name it does not know, which is how a stray space
# fails loudly instead of being quietly repaired.
test_names_reach_the_handler_untrimmed() {
  local format=$1 fixture
  fixture=$(scenario_tmpdir untrimmed)

  {
    stale_region "$format" ' spaced  name '
    stale_region "$format" 'fruit'
  } >"$fixture/source"
  {
    rendered_region "$format" ' spaced  name ' '[ spaced  name ]'
    rendered_region "$format" 'fruit' '[fruit]'
  } >"$fixture/expected"

  render_source "$fixture/result" "$format" "$fixture/source" echo_region_name

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" ' spaced  name ' 'fruit'

  stale_region "$format" 'fruit ' >"$fixture/source"

  render_source "$fixture/refused" "$format" "$fixture/source"

  assert_refused "$fixture/refused"
  assert_handler_calls "$fixture/refused" 'fruit '
}

# Markdown markers are exact, unindented lines. Everything that resembles one
# without being one — indented, followed by whitespace, missing a space, or in
# JSONC's spelling — is prose, copied through untouched.
test_markdown_recognizes_only_exact_unindented_markers() {
  local fixture
  fixture=$(scenario_tmpdir markdown-syntax)

  {
    printf '%s\n' \
      '  <!-- generated: veg -->' \
      '  <!-- generated-end -->' \
      '<!-- generated: veg --> ' \
      '<!-- generated:veg -->' \
      '// generated: veg' \
      '// generated-end' \
      'Prose naming <!-- generated: veg --> inline.'
    stale_region markdown fruit
  } >"$fixture/source"
  {
    printf '%s\n' \
      '  <!-- generated: veg -->' \
      '  <!-- generated-end -->' \
      '<!-- generated: veg --> ' \
      '<!-- generated:veg -->' \
      '// generated: veg' \
      '// generated-end' \
      'Prose naming <!-- generated: veg --> inline.'
    rendered_region markdown fruit '| apple |'
  } >"$fixture/expected"

  render_source "$fixture/result" markdown "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit
}

# JSONC markers are whole-line comments that may be indented, because their
# regions sit inside an object. The indentation is the author's and survives.
test_jsonc_accepts_indented_markers_and_keeps_their_indentation() {
  local fixture
  fixture=$(scenario_tmpdir jsonc-syntax)

  {
    printf '%s\n' \
      '{' \
      '  "note": "mentions // generated: veg",' \
      '  <!-- generated: veg -->' \
      '  //generated: veg' \
      '  "key": true, // generated: veg'
    opening jsonc fruit '    '
    printf '%s\n' '  "stale": true,'
    closing jsonc $'\t'
    printf '%s' '}'
  } >"$fixture/source"
  {
    printf '%s\n' \
      '{' \
      '  "note": "mentions // generated: veg",' \
      '  <!-- generated: veg -->' \
      '  //generated: veg' \
      '  "key": true, // generated: veg'
    opening jsonc fruit '    '
    printf '%s\n' '| apple |'
    closing jsonc $'\t'
    printf '%s' '}'
  } >"$fixture/expected"

  render_source "$fixture/result" jsonc "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit
}

# Invoke the entrypoint with <argument>... and expect a usage error: status 2,
# nothing on stdout, a diagnostic on stderr, and no handler call.
# Usage: expect_usage_error <result-dir> [argument...]
expect_usage_error() {
  local result_dir=$1
  shift

  RENDER_STATUS=0
  scenario_capture "$result_dir" generated_regions_render "$@" \
    || RENDER_STATUS=$?
  assert_equal 2 "$RENDER_STATUS" "status for $(basename -- "$result_dir")"
  assert_empty "$result_dir/stdout.log"
  [ -s "$result_dir/stderr.log" ] \
    || scenario_fail "$(basename -- "$result_dir") needs a usage diagnostic"
  assert_handler_calls "$result_dir"
}

# Usage is the caller's mistake and a refusal is the file's, so the two exit
# differently, and a usage error neither reads the source nor calls the handler.
test_invalid_invocation_is_distinguished_from_a_render_failure() {
  local fixture
  fixture=$(scenario_tmpdir invocation)

  stale_region markdown fruit >"$fixture/source"

  expect_usage_error "$fixture/no-arguments"
  expect_usage_error "$fixture/two-arguments" markdown "$fixture/source"
  expect_usage_error "$fixture/four-arguments" markdown "$fixture/source" \
    render_fixture_region extra
  expect_usage_error "$fixture/unknown-format" yaml "$fixture/source" \
    render_fixture_region
  expect_usage_error "$fixture/empty-format" '' "$fixture/source" \
    render_fixture_region
  expect_usage_error "$fixture/undefined-handler" markdown "$fixture/source" \
    no_such_region_handler
  expect_usage_error "$fixture/usage-before-reading" yaml "$fixture/absent" \
    render_fixture_region
}

for format in "${FORMATS[@]}"; do
  scenario_run "$format: one region is replaced and everything around it kept" \
    test_one_region_is_replaced_and_everything_around_it_kept "$format"
  scenario_run "$format: every region is rendered in file order" \
    test_every_region_is_rendered_in_file_order "$format"
  scenario_run "$format: a repeated name calls the handler once per occurrence" \
    test_a_repeated_name_calls_the_handler_once_per_occurrence "$format"
  scenario_run "$format: an empty body from a successful handler is rendered" \
    test_an_empty_body_from_a_successful_handler_is_rendered "$format"
  scenario_run "$format: a final manual line without a newline is kept" \
    test_a_final_manual_line_without_a_newline_is_kept "$format"
  scenario_run "$format: a closing marker at the end keeps its missing newline" \
    test_a_closing_marker_at_the_end_keeps_its_missing_newline "$format"
  scenario_run "$format: rendering its own output changes nothing" \
    test_rendering_its_own_output_changes_nothing "$format"
  scenario_run "$format: a file without markers is refused" \
    test_a_file_without_markers_is_refused "$format"
  scenario_run "$format: an empty file is refused" \
    test_an_empty_file_is_refused "$format"
  scenario_run "$format: marker mentions in ordinary text are not a region" \
    test_marker_mentions_in_ordinary_text_are_not_a_region "$format"
  scenario_run "$format: an empty region name is refused" \
    test_an_empty_region_name_is_refused "$format"
  scenario_run "$format: a nested opening is refused" \
    test_a_nested_opening_is_refused "$format"
  scenario_run "$format: a closing marker without an opening is refused" \
    test_a_closing_marker_without_an_opening_is_refused "$format"
  scenario_run "$format: a region without a closing marker is refused" \
    test_a_region_without_a_closing_marker_is_refused "$format"
  scenario_run "$format: a closing marker with unsupported whitespace does not close" \
    test_a_closing_marker_with_unsupported_whitespace_does_not_close "$format"
  scenario_run "$format: a name the handler refuses fails the render" \
    test_a_name_the_handler_refuses_fails_the_render "$format"
  scenario_run "$format: a handler failure after part of its body fails the render" \
    test_a_handler_failure_after_part_of_its_body_fails_the_render "$format"
  scenario_run "$format: a handler failure stops the render before later regions" \
    test_a_handler_failure_stops_the_render_before_later_regions "$format"
  scenario_run "$format: an unreadable source is a render failure" \
    test_an_unreadable_source_is_a_render_failure "$format"
  scenario_run "$format: names reach the handler untrimmed" \
    test_names_reach_the_handler_untrimmed "$format"
done
scenario_run 'markdown recognizes only exact unindented markers' \
  test_markdown_recognizes_only_exact_unindented_markers
scenario_run 'jsonc accepts indented markers and keeps their indentation' \
  test_jsonc_accepts_indented_markers_and_keeps_their_indentation
scenario_run 'invalid invocation is distinguished from a render failure' \
  test_invalid_invocation_is_distinguished_from_a_render_failure
scenario_finish
