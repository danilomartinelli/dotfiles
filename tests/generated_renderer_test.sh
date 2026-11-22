#!/usr/bin/env bash
#
# The software catalog renderer at its own seam: what it publishes when
# README.md's generated regions render, and what it leaves alone when they do
# not. The public page's runners render through the same command with --page,
# so the same seam is held for _site/index.html.
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

# The same tree with a copy of the public page beside the declarations.
page_fixture() {
  local fixture
  fixture=$(renderer_fixture "$1")

  mkdir -p "$fixture/_site"
  cp "$REPOSITORY_ROOT/_site/index.html" "$fixture/_site/"
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
    'undescribed-formula has no catalog description'
}

test_a_cask_without_a_description_cannot_be_published() {
  local fixture mode
  fixture=$(renderer_fixture undescribed-cask)
  printf '\n%s\n' '# Editors' "cask 'undescribed-cask'" >>"$fixture/Brewfile"
  cp "$fixture/README.md" "$fixture/before"

  for mode in write check; do
    if [ "$mode" = check ]; then
      run_renderer "$fixture/$mode" "$fixture" --check
    else
      run_renderer "$fixture/$mode" "$fixture"
    fi
    assert_left_intact "$fixture/$mode" "$fixture/README.md" "$fixture/before"
    assert_contains "$fixture/$mode/stderr.log" \
      'undescribed-cask has no catalog description'
  done
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
  assert_contains "$fixture/check/stderr.log" 'stale: README.md'
  assert_contains "$fixture/check/stderr.log" '-| stale |'
  assert_contains "$fixture/check/stderr.log" '+| Formula'
  assert_contains "$fixture/check/stderr.log" \
    'README software catalog is out of date; run _scripts/render-software-catalog'
  assert_equal '' "$(cat "$fixture/check/stdout.log")" 'stale check stdout'
  cmp -s "$fixture/before" "$destination" \
    || scenario_fail '--check wrote the stale file'

  run_renderer "$fixture/write" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'write status'
  assert_contains "$fixture/write/stdout.log" 'rendered README.md'
  cmp -s "$tracked" "$destination" \
    || scenario_fail 'the write did not restore the tracked bytes'

  run_renderer "$fixture/again" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'second write status'
  assert_equal '' "$(cat "$fixture/again/stdout.log")" 'unchanged write stdout'

  run_renderer "$fixture/clean" "$fixture" --check
  assert_equal 0 "$RENDER_STATUS" 'check status after the write'
  assert_contains "$fixture/clean/stdout.log" 'up to date'
  assert_equal '' "$(cat "$fixture/clean/stderr.log")" 'clean check stderr'
}

# A page runner states, per part, what the declaration says and where it is
# written. Whatever a description holds arrives as text, never as markup, and a
# Mise version stays off the page so an upgrade cannot make it stale.
test_page_runners_carry_each_declaration_and_its_line() {
  local fixture page
  fixture=$(page_fixture runners)
  page=$fixture/_site/index.html

  printf '%s\n' \
    "brew 'git'                 # Version control" \
    "brew 'vendor/tap/tool'     # Reads <stdin> & \`tool --json\`" \
    '' \
    '# Editors' \
    "cask 'zed'                 # Code editor" \
    '' \
    "mas 'Xcode', id: 497799835 # Apple IDE" >"$fixture/Brewfile"
  printf '%s\n' \
    '[tools]' \
    '"npm:@scope/cli" = "1.2.3" # Scoped CLI' >"$fixture/mise/config.toml"
  printf '%s\n' \
    '<!-- generated: command-line-tools -->' '<!-- generated-end -->' \
    '<!-- generated: applications-and-fonts -->' '<!-- generated-end -->' \
    '<!-- generated: runtimes-and-clis -->' '<!-- generated-end -->' >"$page"
  cp "$fixture/README.md" "$fixture/readme-before"

  run_renderer "$fixture/result" "$fixture" --page

  assert_equal 0 "$RENDER_STATUS" 'renderer status'
  assert_contains "$fixture/result/stdout.log" 'rendered _site/index.html'
  assert_count "$page" '<p class="runner-count"><b>2</b> parts</p>' 2
  assert_contains "$page" \
    'blob/main/Brewfile#L2"><span class="part-no">A2</span> <span class="part-name">vendor/<wbr>tap/<wbr>tool</span>'
  assert_contains "$page" 'Reads &lt;stdin&gt; &amp; <code>tool --json</code>'
  assert_contains "$page" '<h3 class="part-group">Editors</h3>'
  assert_contains "$page" '<h3 class="part-group">Mac App Store</h3>'
  assert_contains "$page" \
    'blob/main/Brewfile#L7"><span class="part-no">B2</span> <span class="part-name">Xcode</span>'
  assert_contains "$page" \
    'blob/main/mise/config.toml#L2"><span class="part-no">C1</span> <span class="part-name">npm:<wbr>@scope/<wbr>cli</span>'
  assert_not_contains "$page" '1.2.3'
  cmp -s "$fixture/readme-before" "$fixture/README.md" \
    || scenario_fail 'a page render rewrote README.md'
}

# The page generator refuses what it cannot state truthfully, after an earlier
# runner has already been written to the staging file.
test_a_page_generation_failure_leaves_the_page_intact() {
  local fixture page
  fixture=$(page_fixture page-generation)
  page=$fixture/_site/index.html

  printf '%s\n' \
    '<!-- generated: runtimes-and-clis -->' '<li>stale</li>' \
    '<!-- generated-end -->' \
    '<!-- generated: retired-runner -->' '<!-- generated-end -->' >"$page"
  cp "$page" "$fixture/before"

  run_renderer "$fixture/unknown-name" "$fixture" --page

  assert_left_intact "$fixture/unknown-name" "$page" "$fixture/before"
  assert_contains "$fixture/unknown-name/stderr.log" 'retired-runner'

  printf '%s\n' \
    '<!-- generated: runtimes-and-clis -->' '<li>stale</li>' \
    '<!-- generated-end -->' \
    '<!-- generated: command-line-tools -->' '<!-- generated-end -->' >"$page"
  cp "$page" "$fixture/before"
  printf '%s\n' "brew 'half-quoted'  # Runs \`half" >>"$fixture/Brewfile"

  run_renderer "$fixture/backtick" "$fixture" --page

  assert_left_intact "$fixture/backtick" "$page" "$fixture/before"
  assert_contains "$fixture/backtick/stderr.log" \
    'half-quoted has an unclosed backtick in its description'
}

# The repository's own page is current, so the same round trip holds for it,
# and a README render does not reach the page.
test_a_stale_page_is_reported_by_check_and_restored_by_a_write() {
  local fixture page tracked
  fixture=$(page_fixture stale-page)
  page=$fixture/_site/index.html
  tracked=$REPOSITORY_ROOT/_site/index.html

  make_first_region_stale "$page"
  cp "$page" "$fixture/before"
  ! cmp -s "$tracked" "$page" \
    || scenario_fail 'the fixture runner did not go stale'

  run_renderer "$fixture/readme" "$fixture"
  assert_equal 0 "$RENDER_STATUS" 'README render status'
  cmp -s "$fixture/before" "$page" \
    || scenario_fail 'a README render rewrote the page'

  run_renderer "$fixture/check" "$fixture" --check --page
  assert_equal 1 "$RENDER_STATUS" 'check status for a stale runner'
  assert_contains "$fixture/check/stderr.log" 'stale: _site/index.html'
  assert_contains "$fixture/check/stderr.log" '-| stale |'
  assert_contains "$fixture/check/stderr.log" \
    'page software catalog is out of date; run _scripts/render-software-catalog --page'
  assert_equal '' "$(cat "$fixture/check/stdout.log")" 'stale check stdout'
  cmp -s "$fixture/before" "$page" \
    || scenario_fail '--check wrote the stale page'

  run_renderer "$fixture/write" "$fixture" --page
  assert_equal 0 "$RENDER_STATUS" 'write status'
  assert_contains "$fixture/write/stdout.log" 'rendered _site/index.html'
  cmp -s "$tracked" "$page" \
    || scenario_fail 'the write did not restore the tracked bytes'

  run_renderer "$fixture/clean" "$fixture" --check --page
  assert_equal 0 "$RENDER_STATUS" 'check status after the write'
  assert_contains "$fixture/clean/stdout.log" 'page software catalog is up to date'
  assert_equal '' "$(cat "$fixture/clean/stderr.log")" 'clean check stderr'
}

scenario_run 'a marker mention cannot pass for a region' \
  test_a_marker_mention_cannot_pass_for_a_region
scenario_run 'a final manual line without a newline survives a write' \
  test_a_final_manual_line_without_a_newline_survives_a_write
scenario_run 'a malformed region leaves the stored file intact' \
  test_a_malformed_region_leaves_the_stored_file_intact
scenario_run 'a generation failure leaves the stored file intact' \
  test_a_generation_failure_leaves_the_stored_file_intact
scenario_run 'a cask without a description cannot be published' \
  test_a_cask_without_a_description_cannot_be_published
scenario_run 'a rejected declaration leaves the stored file intact' \
  test_a_rejected_declaration_leaves_the_stored_file_intact
scenario_run 'a stale region is reported by check and restored by a write' \
  test_a_stale_region_is_reported_by_check_and_restored_by_a_write
scenario_run 'page runners carry each declaration and its line' \
  test_page_runners_carry_each_declaration_and_its_line
scenario_run 'a page generation failure leaves the page intact' \
  test_a_page_generation_failure_leaves_the_page_intact
scenario_run 'a stale page is reported by check and restored by a write' \
  test_a_stale_page_is_reported_by_check_and_restored_by_a_write
scenario_finish
