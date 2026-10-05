#!/usr/bin/env bash
#
# The software catalog renderer at its own seam: what it publishes when
# README.md's generated regions render, and what it leaves alone when they do
# not.
#
# The region reader streams into the command's staging file, so a failure can
# arrive after an earlier region has already been written there. These cases
# run the command in write mode against isolated fixtures and hold it to
# publishing a file only when its render succeeded. The documentation suite
# runs the same command with --check against a file that is already current,
# which is the one path where nothing can go wrong.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-generated-renderer-tests

RENDERER=$REPOSITORY_ROOT/_scripts/render-software-catalog

# A tree the renderer can run against: the software catalog's declarations
# beside a copy of README.md.
renderer_fixture() {
  local fixture
  fixture=$(scenario_tmpdir "$1")

  mkdir -p "$fixture/mise"
  cp "$REPOSITORY_ROOT/Brewfile" "$REPOSITORY_ROOT/README.md" "$fixture/"
  cp "$REPOSITORY_ROOT/mise/config.toml" "$fixture/mise/"
  printf '%s\n' "$fixture"
}

# Run the renderer against <fixture>, capturing into <result-dir> and setting
# RENDER_STATUS. Extra arguments, such as --check, come first.
# Usage: run_renderer <result-dir> <fixture> [option...]
run_renderer() {
  local result_dir=$1 fixture=$2
  shift 2

  RENDER_STATUS=0
  scenario_capture "$result_dir" "$RENDERER" "$@" "$fixture" \
    || RENDER_STATUS=$?
}

# A failed render publishes nothing: the stored file is byte-for-byte the
# snapshot taken before the run, and nothing was reported as rendered.
assert_left_intact() {
  local result_dir=$1 destination=$2 snapshot=$3

  assert_equal 1 "$RENDER_STATUS" 'renderer status'
  cmp -s -- "$snapshot" "$destination" \
    || scenario_fail "a failed render replaced $destination"
  [ -s "$result_dir/stderr.log" ] \
    || scenario_fail 'a failed render needs a diagnostic'
  assert_not_contains "$result_dir/stdout.log" 'rendered'
}

# Replace the interior of the first region in <file> with a stale line, the
# way a hand edit between the markers would leave it.
make_first_region_stale() {
  awk '
    !done && /^<!-- generated: .* -->$/ { print; print "| stale |"; inside = 1; next }
    inside && /^<!-- generated-end -->$/ { inside = 0; done = 1 }
    !inside { print }
  ' "$1" >"$1.stale"
  mv -- "$1.stale" "$1"
}

# The reader used to search for the marker's prefix and treat a hit as a
# region, so a mention — or an indented marker, which is prose — rendered
# nothing and reported success.
test_a_marker_mention_cannot_pass_for_a_region() {
  local fixture destination
  fixture=$(renderer_fixture mention)
  destination=$fixture/README.md

  printf '%s\n' \
    'Manual mention: <!-- generated: homebrew-formulae -->' \
    '  <!-- generated: homebrew-formulae -->' \
    '  <!-- generated-end -->' >"$destination"
  cp "$destination" "$fixture/before"

  run_renderer "$fixture/result" "$fixture"

  assert_left_intact "$fixture/result" "$destination" "$fixture/before"
}

# The reader also dropped whatever followed the last newline, so a write
# deleted the final hand-written line.
test_a_final_manual_line_without_a_newline_survives_a_write() {
  local fixture destination
  fixture=$(renderer_fixture final-line)
  destination=$fixture/README.md

  printf '%s\n' \
    '# Catalog' \
    '<!-- generated: homebrew-formulae -->' \
    '| stale |' \
    '<!-- generated-end -->' >"$destination"
  printf '%s' 'Last line without a newline' >>"$destination"

  run_renderer "$fixture/result" "$fixture"

  assert_equal 0 "$RENDER_STATUS" 'renderer status'
  assert_not_contains "$destination" '| stale |'
  [ -n "$(tail -c 1 "$destination")" ] \
    || scenario_fail 'the write added a final newline the source did not have'
  assert_equal 'Last line without a newline' "$(tail -n 1 "$destination")" \
    'final manual line'
  assert_contains "$destination" '| Formula'
}

# A malformed region is found after an earlier region was already rendered
# into the staging file. None of that may reach the stored file.
test_a_malformed_region_leaves_the_stored_file_intact() {
  local fixture destination malformation
  fixture=$(renderer_fixture malformed)
  destination=$fixture/README.md

  for malformation in unterminated orphan-closing; do
    case "$malformation" in
      unterminated)
        printf '%s\n' \
          '<!-- generated: homebrew-formulae -->' '| stale |' \
          '<!-- generated-end -->' \
          '<!-- generated: mise-tools -->' 'the rest of the file' >"$destination"
        ;;
      orphan-closing)
        printf '%s\n' \
          '<!-- generated: homebrew-formulae -->' '| stale |' \
          '<!-- generated-end -->' 'between' \
          '<!-- generated-end -->' >"$destination"
        ;;
    esac
    cp "$destination" "$fixture/before"

    run_renderer "$fixture/$malformation" "$fixture"

    assert_left_intact "$fixture/$malformation" "$destination" "$fixture/before"
  done
}

# Generation fails after an earlier region has emitted its body: a name the
# renderer's handler refuses, and a declaration its generator rejects.
test_a_generation_failure_leaves_the_stored_file_intact() {
  local fixture destination
  fixture=$(renderer_fixture generation)
  destination=$fixture/README.md

  printf '%s\n' \
    '<!-- generated: mise-tools -->' '| stale |' '<!-- generated-end -->' \
    '<!-- generated: retired-region -->' '<!-- generated-end -->' \
    >"$destination"
  cp "$destination" "$fixture/before"

  run_renderer "$fixture/unknown-name" "$fixture"

  assert_left_intact "$fixture/unknown-name" "$destination" "$fixture/before"
  assert_contains "$fixture/unknown-name/stderr.log" 'retired-region'

  printf '%s\n' \
    '<!-- generated: mise-tools -->' '| stale |' '<!-- generated-end -->' \
    '<!-- generated: homebrew-formulae -->' '<!-- generated-end -->' \
    >"$destination"
  cp "$destination" "$fixture/before"
  printf '%s\n' "brew 'undescribed-formula'" >>"$fixture/Brewfile"

  run_renderer "$fixture/generator" "$fixture"

  assert_left_intact "$fixture/generator" "$destination" "$fixture/before"
  assert_contains "$fixture/generator/stderr.log" \
    'brew undescribed-formula has no catalog description'
}

# A Brewfile line outside the grammar the declaration reader accepts stops the
# render too, after an earlier region has already emitted its body.
test_a_rejected_declaration_leaves_the_stored_file_intact() {
  local fixture destination
  fixture=$(renderer_fixture rejected)
  destination=$fixture/README.md

  printf '%s\n' \
    '<!-- generated: mise-tools -->' '| stale |' '<!-- generated-end -->' \
    '<!-- generated: homebrew-formulae -->' '<!-- generated-end -->' \
    >"$destination"
  cp "$destination" "$fixture/before"
  printf '%s\n' "brew 'git', args: ['HEAD']" >>"$fixture/Brewfile"

  run_renderer "$fixture/result" "$fixture"

  assert_left_intact "$fixture/result" "$destination" "$fixture/before"
  assert_contains "$fixture/result/stderr.log" 'not a literal Brewfile declaration'
}

# The repository's own README.md is current, so rendering a copy whose region
# was edited by hand must restore exactly the tracked bytes, --check must
# report the drift without writing it, and a second write must find nothing to
# do.
test_a_stale_region_is_reported_by_check_and_restored_by_a_write() {
  local fixture destination tracked
  fixture=$(renderer_fixture stale)
  destination=$fixture/README.md
  tracked=$REPOSITORY_ROOT/README.md

  make_first_region_stale "$destination"
  cp "$destination" "$fixture/before"
  ! cmp -s "$tracked" "$destination" \
    || scenario_fail 'the fixture region did not go stale'

  run_renderer "$fixture/check" "$fixture" --check
  assert_equal 1 "$RENDER_STATUS" 'check status for a stale region'
  assert_contains "$fixture/check/stderr.log" 'stale: '
  assert_contains "$fixture/check/stderr.log" 'out of date (1 file(s))'
  cmp -s "$fixture/before" "$destination" \
    || scenario_fail '--check wrote the stale file'

  run_renderer "$fixture/write" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'write status'
  assert_contains "$fixture/write/stdout.log" 'rendered'
  cmp -s "$tracked" "$destination" \
    || scenario_fail 'the write did not restore the tracked bytes'

  run_renderer "$fixture/again" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'second write status'
  assert_not_contains "$fixture/again/stdout.log" 'rendered'

  run_renderer "$fixture/clean" "$fixture" --check
  assert_equal 0 "$RENDER_STATUS" 'check status after the write'
  assert_contains "$fixture/clean/stdout.log" 'up to date'
}

scenario_run 'a marker mention cannot pass for a region' \
  test_a_marker_mention_cannot_pass_for_a_region
scenario_run 'a final manual line without a newline survives a write' \
  test_a_final_manual_line_without_a_newline_survives_a_write
scenario_run 'a malformed region leaves the stored file intact' \
  test_a_malformed_region_leaves_the_stored_file_intact
scenario_run 'a generation failure leaves the stored file intact' \
  test_a_generation_failure_leaves_the_stored_file_intact
scenario_run 'a rejected declaration leaves the stored file intact' \
  test_a_rejected_declaration_leaves_the_stored_file_intact
scenario_run 'a stale region is reported by check and restored by a write' \
  test_a_stale_region_is_reported_by_check_and_restored_by_a_write
scenario_finish
