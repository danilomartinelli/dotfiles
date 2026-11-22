#!/usr/bin/env bash
#
# The public page as it is published: static files that ask nothing of any
# other server.
#
# GitHub Pages serves _site/ exactly as it is tracked, so nothing between the
# checkout and a visitor can add a missing file or repair a broken reference.
# These cases hold the tracked files to what the page states about itself: it
# runs no script, it loads every resource from its own directory, and every
# link inside the page lands somewhere. The last one holds the deployment to
# waiting for CI.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-site-tests

SITE=$REPOSITORY_ROOT/_site
PAGE=$SITE/index.html

# Print every resource the browser fetches to draw the page: what a <link>
# names, anything with a src, and each url() in a stylesheet. A fragment that
# points inside the document is not a fetch and is left out.
page_resources() {
  local stylesheet

  grep -oE '<link[^>]* href="[^"]*"' "$PAGE" | sed 's/.* href="//; s/"$//' || true
  grep -oE '[[:space:]]src="[^"]*"' "$PAGE" | sed 's/.*src="//; s/"$//' || true
  for stylesheet in "$SITE"/*.css; do
    grep -oE 'url\([^)]*\)' "$stylesheet" | sed 's/^url(//; s/)$//; s/"//g' || true
  done
}

test_the_page_runs_no_script() {
  assert_not_contains "$PAGE" '<script'
  assert_not_contains "$PAGE" 'javascript:'
}

test_every_resource_is_a_tracked_file_beside_the_page() {
  local resource resources
  resources=$(page_resources)

  [ -n "$resources" ] || scenario_fail 'the page names no resource to check'
  while IFS= read -r resource; do
    case "$resource" in
      *:* | /*)
        scenario_fail "the page loads a resource from outside its directory: $resource"
        ;;
    esac
    [ -f "$SITE/$resource" ] \
      || scenario_fail "the page names a resource that does not exist: $resource"
  done <<<"$resources"
}

test_every_link_inside_the_page_has_a_target() {
  local fragment fragments
  fragments=$(grep -oE 'href="#[^"]+"' "$PAGE" | sed 's/^href="#//; s/"$//' | sort -u)

  [ -n "$fragments" ] || scenario_fail 'the page holds no internal link to check'
  while IFS= read -r fragment; do
    grep -Fq -- " id=\"$fragment\"" "$PAGE" \
      || scenario_fail "the page links to a missing target: #$fragment"
  done <<<"$fragments"
}

# The page is published as tracked, so the only gate between a broken page and
# a visitor is that the deployment waits for CI and publishes this directory.
test_the_page_is_published_only_after_ci_passes() {
  local workflow=$REPOSITORY_ROOT/.github/workflows/pages.yml

  assert_contains "$workflow" 'workflows: [CI]'
  assert_contains "$workflow" "github.event.workflow_run.conclusion == 'success'"
  assert_contains "$workflow" 'github.event.workflow_run.head_sha || github.sha'
  assert_contains "$workflow" 'path: _site'
}

scenario_run 'the page runs no script' \
  test_the_page_runs_no_script
scenario_run 'every resource is a tracked file beside the page' \
  test_every_resource_is_a_tracked_file_beside_the_page
scenario_run 'every link inside the page has a target' \
  test_every_link_inside_the_page_has_a_target
scenario_run 'the page is published only after CI passes' \
  test_the_page_is_published_only_after_ci_passes
scenario_finish
