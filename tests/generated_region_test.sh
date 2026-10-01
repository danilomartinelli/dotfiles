#!/usr/bin/env bash
#
# Generated regions inside hand-authored Markdown.
#
# Every structural guarantee here runs through the public entrypoint, with a
# real source file and a small handler. Marker spelling, the refusal of
# indented markers, and the padding around a body are asserted as exact bytes,
# because a comparison through command substitution would strip the very
# newlines several of these cases are about.

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

# One marker line, newline included.
opening() {
  printf '<!-- generated: %s -->\n' "$1"
}

# Indentation is a parameter so that a case can offer it and see it refused.
# Usage: closing [indentation]
closing() {
  printf '%s<!-- generated-end -->\n' "${1-}"
}

# A body is set off with a blank line on each side, which is where mdformat
# puts them.
padding() {
  printf '\n'
}

# A region as it sits in a source: markers around an interior the render must
# discard.
stale_region() {
  opening "$1"
  printf '%s\n' '| stale |' 'stale interior'
  closing
}

# A region as it must come out: the same markers around the handler's body.
# Usage: rendered_region <name> [body-line...]
rendered_region() {
  local name=$1
  shift

  opening "$name"
  padding
  [ "$#" -eq 0 ] || printf '%s\n' "$@"
  padding
  closing
}

# Render <source> through the public entrypoint into <result-dir>, setting
# RENDER_STATUS. The reader never writes the file it reads, so every render
# also proves the source is byte-for-byte what it was.
# Usage: render_source <result-dir> <source> [handler]
render_source() {
  local result_dir=$1 source=$2
  local handler=${3:-render_fixture_region}

  mkdir -p -- "$result_dir"
  cp -- "$source" "$result_dir/source.before"
  RENDER_STATUS=0
  scenario_capture "$result_dir" \
    generated_regions_render "$source" "$handler" \
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
  local fixture
  fixture=$(scenario_tmpdir one-region)

  {
    printf '%s\n' 'Manual text before.' '' '  indented manual line'
    stale_region fruit
    printf '%s\n' '' 'Manual text after.'
  } >"$fixture/source"
  {
    printf '%s\n' 'Manual text before.' '' '  indented manual line'
    rendered_region fruit '| apple |'
    printf '%s\n' '' 'Manual text after.'
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit
}

test_every_region_is_rendered_in_file_order() {
  local fixture
  fixture=$(scenario_tmpdir many-regions)

  {
    printf '%s\n' 'before'
    stale_region fruit
    printf '%s\n' 'between'
    stale_region veg
    printf '%s\n' 'after'
  } >"$fixture/source"
  {
    printf '%s\n' 'before'
    rendered_region fruit '| apple |'
    printf '%s\n' 'between'
    rendered_region veg '| leek |' '| kale |'
    printf '%s\n' 'after'
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit veg
}

test_a_repeated_name_calls_the_handler_once_per_occurrence() {
  local fixture
  fixture=$(scenario_tmpdir repeated)

  {
    stale_region fruit
    stale_region veg
    printf '%s\n' 'between'
    stale_region fruit
  } >"$fixture/source"
  {
    rendered_region fruit '| apple |'
    rendered_region veg '| leek |' '| kale |'
    printf '%s\n' 'between'
    rendered_region fruit '| apple |'
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" fruit veg fruit
}

test_an_empty_body_from_a_successful_handler_is_rendered() {
  local fixture
  fixture=$(scenario_tmpdir empty-body)

  stale_region empty >"$fixture/source"
  rendered_region empty >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" empty
}

# The reader used to read the file a line at a time and drop whatever followed
# the last newline, so the render deleted hand-written text.
test_a_final_manual_line_without_a_newline_is_kept() {
  local fixture
  fixture=$(scenario_tmpdir final-line)

  {
    stale_region fruit
    printf '%s' 'last manual line'
  } >"$fixture/source"
  {
    rendered_region fruit '| apple |'
    printf '%s' 'last manual line'
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
}

test_a_closing_marker_at_the_end_keeps_its_missing_newline() {
  local fixture
  fixture=$(scenario_tmpdir final-marker)

  {
    printf '%s\n' 'before'
    opening fruit
    printf '%s\n' '| stale |'
    printf '%s' "$(closing)"
  } >"$fixture/source"
  {
    printf '%s\n' 'before'
    opening fruit
    padding
    printf '%s\n' '| apple |'
    padding
    printf '%s' "$(closing)"
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

  assert_rendered "$fixture/result" "$fixture/expected"
}

test_rendering_its_own_output_changes_nothing() {
  local fixture
  fixture=$(scenario_tmpdir idempotent)

  {
    printf '%s\n' 'before'
    stale_region fruit
    printf '%s\n' 'between'
    stale_region empty
    printf '%s' 'after'
  } >"$fixture/source"

  render_source "$fixture/first" "$fixture/source"
  assert_equal 0 "$RENDER_STATUS" 'first render status'
  cp "$fixture/first/stdout.log" "$fixture/rendered"

  render_source "$fixture/second" "$fixture/rendered"

  assert_rendered "$fixture/second" "$fixture/rendered"
}

test_a_file_without_markers_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir no-markers)

  printf '%s\n' '# Heading' '' 'Only prose.' >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

test_an_empty_file_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir empty-file)

  : >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

# The reader once searched the file for the marker's prefix and took a hit as
# proof a region existed, so a mention in prose — or a marker that is indented
# and therefore not one — rendered nothing and reported success.
test_marker_mentions_in_ordinary_text_are_not_a_region() {
  local fixture
  fixture=$(scenario_tmpdir mentions)

  printf '%s\n' \
    'A region opens with <!-- generated: fruit --> on a line of its own.' \
    '  <!-- generated: fruit -->' \
    '  <!-- generated-end -->' >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

test_an_empty_region_name_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir empty-name)

  {
    printf '%s\n' 'before'
    opening ''
    printf '%s\n' '| stale |'
    closing
  } >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result"
}

test_a_nested_opening_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir nested)

  {
    opening fruit
    opening veg
    closing
    closing
  } >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
}

test_a_closing_marker_without_an_opening_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir orphan)

  {
    stale_region fruit
    printf '%s\n' 'between'
    closing
  } >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
}

test_a_region_without_a_closing_marker_is_refused() {
  local fixture
  fixture=$(scenario_tmpdir unterminated)

  {
    stale_region fruit
    opening veg
    printf '%s\n' 'the rest of the file'
  } >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"
  assert_refused "$fixture/result"

  printf '%s' "$(opening fruit)" >"$fixture/source"

  render_source "$fixture/last-line" "$fixture/source"
  assert_refused "$fixture/last-line"
}

# A marker that is almost one is text, including in the closing position:
# accepting it there would widen the syntax the reader treats as structure.
test_a_closing_marker_with_unsupported_whitespace_does_not_close() {
  local fixture
  fixture=$(scenario_tmpdir closing-whitespace)

  {
    opening fruit
    printf '%s \n' "$(closing)"
  } >"$fixture/source"

  render_source "$fixture/trailing" "$fixture/source"
  assert_refused "$fixture/trailing"

  {
    opening fruit
    closing '  '
  } >"$fixture/source"

  render_source "$fixture/indented" "$fixture/source"
  assert_refused "$fixture/indented"
}

test_a_name_the_handler_refuses_fails_the_render() {
  local fixture
  fixture=$(scenario_tmpdir unknown-name)

  stale_region mystery >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
  assert_contains "$fixture/result/stderr.log" 'fixture: unknown region: mystery'
  assert_handler_calls "$fixture/result" mystery
}

test_a_handler_failure_after_part_of_its_body_fails_the_render() {
  local fixture
  fixture=$(scenario_tmpdir partial-body)

  stale_region partial >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
}

test_a_handler_failure_stops_the_render_before_later_regions() {
  local fixture
  fixture=$(scenario_tmpdir stops)

  {
    stale_region fruit
    stale_region mystery
    stale_region veg
  } >"$fixture/source"

  render_source "$fixture/result" "$fixture/source"

  assert_refused "$fixture/result"
  assert_handler_calls "$fixture/result" fruit mystery
}

test_an_unreadable_source_is_a_render_failure() {
  local fixture
  fixture=$(scenario_tmpdir unreadable)
  mkdir "$fixture/directory"

  RENDER_STATUS=0
  scenario_capture "$fixture/missing" generated_regions_render \
    "$fixture/absent" render_fixture_region || RENDER_STATUS=$?
  assert_refused "$fixture/missing"
  assert_handler_calls "$fixture/missing"

  RENDER_STATUS=0
  scenario_capture "$fixture/not-a-file" generated_regions_render \
    "$fixture/directory" render_fixture_region || RENDER_STATUS=$?
  assert_refused "$fixture/not-a-file"
  assert_handler_calls "$fixture/not-a-file"

  # A file that exists but cannot be read is as unavailable as an absent one.
  stale_region fruit >"$fixture/sealed"
  chmod 000 "$fixture/sealed"
  RENDER_STATUS=0
  scenario_capture "$fixture/unreadable" generated_regions_render \
    "$fixture/sealed" render_fixture_region || RENDER_STATUS=$?
  chmod 600 "$fixture/sealed"
  assert_refused "$fixture/unreadable"
  assert_handler_calls "$fixture/unreadable"
}

# Names reach the handler exactly as written between the marker's fixed parts.
# The handler then refuses a name it does not know, which is how a stray space
# fails loudly instead of being quietly repaired.
test_names_reach_the_handler_untrimmed() {
  local fixture
  fixture=$(scenario_tmpdir untrimmed)

  {
    stale_region ' spaced  name '
    stale_region 'fruit'
  } >"$fixture/source"
  {
    rendered_region ' spaced  name ' '[ spaced  name ]'
    rendered_region 'fruit' '[fruit]'
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source" echo_region_name

  assert_rendered "$fixture/result" "$fixture/expected"
  assert_handler_calls "$fixture/result" ' spaced  name ' 'fruit'

  stale_region 'fruit ' >"$fixture/source"

  render_source "$fixture/refused" "$fixture/source"

  assert_refused "$fixture/refused"
  assert_handler_calls "$fixture/refused" 'fruit '
}

# Markers are exact, unindented lines. Everything that resembles one without
# being one — indented, followed by whitespace, missing a space, or spelled as
# a line comment — is prose, copied through untouched.
test_only_exact_unindented_markers_are_recognized() {
  local fixture
  fixture=$(scenario_tmpdir marker-syntax)

  {
    printf '%s\n' \
      '  <!-- generated: veg -->' \
      '  <!-- generated-end -->' \
      '<!-- generated: veg --> ' \
      '<!-- generated:veg -->' \
      '// generated: veg' \
      '// generated-end' \
      'Prose naming <!-- generated: veg --> inline.'
    stale_region fruit
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
    rendered_region fruit '| apple |'
  } >"$fixture/expected"

  render_source "$fixture/result" "$fixture/source"

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

  stale_region fruit >"$fixture/source"

  expect_usage_error "$fixture/no-arguments"
  expect_usage_error "$fixture/one-argument" "$fixture/source"
  expect_usage_error "$fixture/three-arguments" "$fixture/source" \
    render_fixture_region extra
  expect_usage_error "$fixture/undefined-handler" "$fixture/source" \
    no_such_region_handler
  expect_usage_error "$fixture/empty-handler" "$fixture/source" ''
  expect_usage_error "$fixture/usage-before-reading" "$fixture/absent" \
    no_such_region_handler
}

scenario_run 'one region is replaced and everything around it kept' \
  test_one_region_is_replaced_and_everything_around_it_kept
scenario_run 'every region is rendered in file order' \
  test_every_region_is_rendered_in_file_order
scenario_run 'a repeated name calls the handler once per occurrence' \
  test_a_repeated_name_calls_the_handler_once_per_occurrence
scenario_run 'an empty body from a successful handler is rendered' \
  test_an_empty_body_from_a_successful_handler_is_rendered
scenario_run 'a final manual line without a newline is kept' \
  test_a_final_manual_line_without_a_newline_is_kept
scenario_run 'a closing marker at the end keeps its missing newline' \
  test_a_closing_marker_at_the_end_keeps_its_missing_newline
scenario_run 'rendering its own output changes nothing' \
  test_rendering_its_own_output_changes_nothing
scenario_run 'a file without markers is refused' \
  test_a_file_without_markers_is_refused
scenario_run 'an empty file is refused' \
  test_an_empty_file_is_refused
scenario_run 'marker mentions in ordinary text are not a region' \
  test_marker_mentions_in_ordinary_text_are_not_a_region
scenario_run 'an empty region name is refused' \
  test_an_empty_region_name_is_refused
scenario_run 'a nested opening is refused' \
  test_a_nested_opening_is_refused
scenario_run 'a closing marker without an opening is refused' \
  test_a_closing_marker_without_an_opening_is_refused
scenario_run 'a region without a closing marker is refused' \
  test_a_region_without_a_closing_marker_is_refused
scenario_run 'a closing marker with unsupported whitespace does not close' \
  test_a_closing_marker_with_unsupported_whitespace_does_not_close
scenario_run 'a name the handler refuses fails the render' \
  test_a_name_the_handler_refuses_fails_the_render
scenario_run 'a handler failure after part of its body fails the render' \
  test_a_handler_failure_after_part_of_its_body_fails_the_render
scenario_run 'a handler failure stops the render before later regions' \
  test_a_handler_failure_stops_the_render_before_later_regions
scenario_run 'an unreadable source is a render failure' \
  test_an_unreadable_source_is_a_render_failure
scenario_run 'names reach the handler untrimmed' \
  test_names_reach_the_handler_untrimmed
scenario_run 'only exact unindented markers are recognized' \
  test_only_exact_unindented_markers_are_recognized
scenario_run 'invalid invocation is distinguished from a render failure' \
  test_invalid_invocation_is_distinguished_from_a_render_failure
scenario_finish
