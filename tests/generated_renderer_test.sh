#!/usr/bin/env bash
#
# The renderer commands at their own seam: what each one publishes when its
# generated regions render, and what it leaves alone when they do not.
#
# The region reader streams into the command's staging file, so a failure can
# arrive after an earlier region has already been written there. These cases
# run the commands in write mode against isolated fixtures and hold them to
# publishing a file only when its render succeeded. The documentation and
# OpenCode suites run the same commands with --check against files that are
# already current, which is the one path where nothing can go wrong.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/jsonc.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/jsonc.sh"
scenario_init dotfiles-generated-renderer-tests

FORMATS=(markdown jsonc)

# A tree the format's renderer can run against: the software catalog's
# declarations beside a copy of README.md, or a copy of the OpenCode topic.
renderer_fixture() {
  local fixture
  fixture=$(scenario_tmpdir "$1")

  case "$1" in
    markdown)
      mkdir -p "$fixture/mise"
      cp "$REPOSITORY_ROOT/Brewfile" "$REPOSITORY_ROOT/README.md" "$fixture/"
      cp "$REPOSITORY_ROOT/mise/config.toml" "$fixture/mise/"
      ;;
    jsonc)
      tar -C "$REPOSITORY_ROOT/opencode" --exclude=node_modules -cf - . \
        | tar -C "$fixture" -xf -
      ;;
  esac
  printf '%s\n' "$fixture"
}

# The hand-authored file each renderer writes generated regions into.
renderer_destination() {
  case "$1" in
    markdown) printf '%s/README.md\n' "$2" ;;
    jsonc) printf '%s/opencode.jsonc\n' "$2" ;;
  esac
}

# Run the format's renderer against <fixture>, capturing into <result-dir> and
# setting RENDER_STATUS. Extra arguments, such as --check, come first.
# Usage: run_renderer <result-dir> <format> <fixture> [option...]
run_renderer() {
  local result_dir=$1 format=$2 fixture=$3 command
  shift 3

  case "$format" in
    markdown) command=$REPOSITORY_ROOT/_scripts/render-software-catalog ;;
    jsonc) command=$REPOSITORY_ROOT/_scripts/render-opencode-profiles ;;
  esac
  RENDER_STATUS=0
  scenario_capture "$result_dir" "$command" "$@" "$fixture" \
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
  local format=$1 file=$2 opening_pattern closing_pattern stale

  case "$format" in
    markdown)
      opening_pattern='^<!-- generated: .* -->$'
      closing_pattern='^<!-- generated-end -->$'
      stale='| stale |'
      ;;
    jsonc)
      opening_pattern='^[[:space:]]*// generated: '
      closing_pattern='^[[:space:]]*// generated-end$'
      stale='  "stale": true,'
      ;;
  esac
  awk -v opening="$opening_pattern" -v closing="$closing_pattern" \
    -v stale="$stale" '
      !done && $0 ~ opening { print; print stale; inside = 1; next }
      inside && $0 ~ closing { inside = 0; done = 1 }
      !inside { print }
    ' "$file" >"$file.stale"
  mv -- "$file.stale" "$file"
}

# Both readers used to search for the marker's prefix and treat a hit as a
# region, so a mention — or an indented Markdown marker, which is prose —
# rendered nothing and reported success.
test_a_marker_mention_cannot_pass_for_a_region() {
  local format=$1 fixture destination
  fixture=$(renderer_fixture "$format")
  destination=$(renderer_destination "$format" "$fixture")

  case "$format" in
    markdown)
      printf '%s\n' \
        'Manual mention: <!-- generated: homebrew-formulae -->' \
        '  <!-- generated: homebrew-formulae -->' \
        '  <!-- generated-end -->' >"$destination"
      ;;
    jsonc)
      printf '%s\n' \
        '{ "note": "Mention // generated: default-profile" }' >"$destination"
      ;;
  esac
  cp "$destination" "$fixture/before"

  run_renderer "$fixture/result" "$format" "$fixture"

  assert_left_intact "$fixture/result" "$destination" "$fixture/before"
}

# The readers also dropped whatever followed the last newline, so a write
# deleted the final hand-written line — for JSONC, the closing brace.
test_a_final_manual_line_without_a_newline_survives_a_write() {
  local format=$1 fixture destination
  fixture=$(renderer_fixture "$format")
  destination=$(renderer_destination "$format" "$fixture")

  case "$format" in
    markdown)
      printf '%s\n' \
        '# Catalog' \
        '<!-- generated: homebrew-formulae -->' \
        '| stale |' \
        '<!-- generated-end -->' >"$destination"
      printf '%s' 'Last line without a newline' >>"$destination"
      ;;
    jsonc)
      # shellcheck disable=SC2016 # A literal JSON key, not an expansion.
      printf '%s\n' \
        '{' \
        '  "$schema": "https://opencode.ai/config.json",' \
        '  // generated: default-profile' \
        '  "stale": true,' \
        '  // generated-end' \
        '  "autoupdate": false' >"$destination"
      printf '%s' '}' >>"$destination"
      ;;
  esac

  run_renderer "$fixture/result" "$format" "$fixture"

  assert_equal 0 "$RENDER_STATUS" 'renderer status'
  assert_not_contains "$destination" '| stale |'
  assert_not_contains "$destination" '"stale": true'
  [ -n "$(tail -c 1 "$destination")" ] \
    || scenario_fail 'the write added a final newline the source did not have'
  case "$format" in
    markdown)
      assert_equal 'Last line without a newline' "$(tail -n 1 "$destination")" \
        'final manual line'
      assert_contains "$destination" '| Formula'
      ;;
    jsonc)
      assert_equal '}' "$(tail -n 1 "$destination")" 'final manual line'
      jsonc_to_json "$destination" \
        | jq -e '.autoupdate == false and (.model | type) == "string"' >/dev/null \
        || scenario_fail 'the written config is not the rendered JSONC'
      ;;
  esac
}

# A malformed region is found after an earlier region was already rendered
# into the staging file. None of that may reach the stored file.
test_a_malformed_region_leaves_the_stored_file_intact() {
  local format=$1 fixture destination malformation
  fixture=$(renderer_fixture "$format")
  destination=$(renderer_destination "$format" "$fixture")

  for malformation in unterminated orphan-closing; do
    case "$format:$malformation" in
      markdown:unterminated)
        printf '%s\n' \
          '<!-- generated: homebrew-formulae -->' '| stale |' \
          '<!-- generated-end -->' \
          '<!-- generated: mise-tools -->' 'the rest of the file' >"$destination"
        ;;
      markdown:orphan-closing)
        printf '%s\n' \
          '<!-- generated: homebrew-formulae -->' '| stale |' \
          '<!-- generated-end -->' 'between' \
          '<!-- generated-end -->' >"$destination"
        ;;
      jsonc:unterminated)
        printf '%s\n' \
          '{' '  // generated: default-profile' '  "stale": true,' \
          '  // generated-end' '  // generated: default-profile' \
          '  "autoupdate": false' '}' >"$destination"
        ;;
      jsonc:orphan-closing)
        printf '%s\n' \
          '{' '  // generated: default-profile' '  "stale": true,' \
          '  // generated-end' '  // generated-end' \
          '  "autoupdate": false' '}' >"$destination"
        ;;
    esac
    cp "$destination" "$fixture/before"

    run_renderer "$fixture/$malformation" "$format" "$fixture"

    assert_left_intact "$fixture/$malformation" "$destination" "$fixture/before"
  done
}

# Generation fails after an earlier region has emitted its body: a name the
# renderer's handler refuses, and for the catalog a declaration its generator
# rejects.
test_a_generation_failure_leaves_the_stored_file_intact() {
  local format=$1 fixture destination
  fixture=$(renderer_fixture "$format")
  destination=$(renderer_destination "$format" "$fixture")

  case "$format" in
    markdown)
      printf '%s\n' \
        '<!-- generated: mise-tools -->' '| stale |' '<!-- generated-end -->' \
        '<!-- generated: retired-region -->' '<!-- generated-end -->' \
        >"$destination"
      ;;
    jsonc)
      printf '%s\n' \
        '{' '  // generated: default-profile' '  "stale": true,' \
        '  // generated-end' '  // generated: retired-region' \
        '  // generated-end' '  "autoupdate": false' '}' >"$destination"
      ;;
  esac
  cp "$destination" "$fixture/before"

  run_renderer "$fixture/unknown-name" "$format" "$fixture"

  assert_left_intact "$fixture/unknown-name" "$destination" "$fixture/before"
  assert_contains "$fixture/unknown-name/stderr.log" 'retired-region'

  [ "$format" = markdown ] || return 0

  printf '%s\n' \
    '<!-- generated: mise-tools -->' '| stale |' '<!-- generated-end -->' \
    '<!-- generated: homebrew-formulae -->' '<!-- generated-end -->' \
    >"$destination"
  cp "$destination" "$fixture/before"
  printf '%s\n' "brew 'undescribed-formula'" >>"$fixture/Brewfile"

  run_renderer "$fixture/generator" "$format" "$fixture"

  assert_left_intact "$fixture/generator" "$destination" "$fixture/before"
  assert_contains "$fixture/generator/stderr.log" \
    'brew undescribed-formula has no catalog description'
}

# The repository's own files are current, so rendering a copy whose region was
# edited by hand must restore exactly the tracked bytes, --check must report
# the drift without writing it, and a second write must find nothing to do.
test_a_stale_region_is_reported_by_check_and_restored_by_a_write() {
  local format=$1 fixture destination tracked
  fixture=$(renderer_fixture "$format")
  destination=$(renderer_destination "$format" "$fixture")
  case "$format" in
    markdown) tracked=$REPOSITORY_ROOT/README.md ;;
    jsonc) tracked=$REPOSITORY_ROOT/opencode/opencode.jsonc ;;
  esac

  make_first_region_stale "$format" "$destination"
  cp "$destination" "$fixture/before"
  ! cmp -s "$tracked" "$destination" \
    || scenario_fail 'the fixture region did not go stale'

  run_renderer "$fixture/check" "$format" "$fixture" --check
  assert_equal 1 "$RENDER_STATUS" 'check status for a stale region'
  assert_contains "$fixture/check/stderr.log" 'stale: '
  assert_contains "$fixture/check/stderr.log" 'out of date (1 file(s))'
  cmp -s "$fixture/before" "$destination" \
    || scenario_fail '--check wrote the stale file'

  run_renderer "$fixture/write" "$format" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'write status'
  assert_contains "$fixture/write/stdout.log" 'rendered'
  cmp -s "$tracked" "$destination" \
    || scenario_fail 'the write did not restore the tracked bytes'

  run_renderer "$fixture/again" "$format" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'second write status'
  assert_not_contains "$fixture/again/stdout.log" 'rendered'

  run_renderer "$fixture/clean" "$format" "$fixture" --check
  assert_equal 0 "$RENDER_STATUS" 'check status after the write'
  assert_contains "$fixture/clean/stdout.log" 'up to date'
}

# The lines outside every region interior in a JSONC file: the markers and the
# hand-authored configuration around them.
jsonc_outside_regions() {
  awk '
    /^[[:space:]]*\/\/ generated-end$/ { inside = 0 }
    !inside { print }
    /^[[:space:]]*\/\/ generated: / { inside = 1 }
  ' "$1"
}

# ADR-0018: the global config carries whichever profile env.zsh declares as
# the default, and only its generated region follows that declaration.
test_the_global_config_follows_the_declared_default_profile() {
  local fixture destination
  fixture=$(renderer_fixture jsonc)
  destination=$fixture/opencode.jsonc

  jsonc_outside_regions "$destination" >"$fixture/manual.before"
  sed "s/^export OCX_PROFILE=.*/export OCX_PROFILE='anthropic'/" \
    "$fixture/env.zsh" >"$fixture/env.zsh.next"
  mv "$fixture/env.zsh.next" "$fixture/env.zsh"

  run_renderer "$fixture/check" jsonc "$fixture" --check
  assert_equal 1 "$RENDER_STATUS" 'check status after a default change'
  assert_contains "$fixture/check/stderr.log" "stale: $destination"

  run_renderer "$fixture/write" jsonc "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'write status'

  jsonc_to_json "$destination" \
    | jq -S '{model, small_model, agent}' >"$fixture/global.routes"
  jsonc_to_json "$fixture/profiles/anthropic/opencode.jsonc" \
    | jq -S '{model, small_model, agent}' >"$fixture/anthropic.routes"
  cmp -s "$fixture/anthropic.routes" "$fixture/global.routes" \
    || scenario_fail 'the global config does not carry the anthropic routes'

  jsonc_outside_regions "$destination" >"$fixture/manual.after"
  cmp -s "$fixture/manual.before" "$fixture/manual.after" \
    || scenario_fail 'the manual configuration around the region changed'
}

for format in "${FORMATS[@]}"; do
  scenario_run "$format: a marker mention cannot pass for a region" \
    test_a_marker_mention_cannot_pass_for_a_region "$format"
  scenario_run "$format: a final manual line without a newline survives a write" \
    test_a_final_manual_line_without_a_newline_survives_a_write "$format"
  scenario_run "$format: a malformed region leaves the stored file intact" \
    test_a_malformed_region_leaves_the_stored_file_intact "$format"
  scenario_run "$format: a generation failure leaves the stored file intact" \
    test_a_generation_failure_leaves_the_stored_file_intact "$format"
  scenario_run "$format: a stale region is reported by check and restored by a write" \
    test_a_stale_region_is_reported_by_check_and_restored_by_a_write "$format"
done
scenario_run 'jsonc: the global config follows the declared default profile' \
  test_the_global_config_follows_the_declared_default_profile
scenario_finish
