#!/usr/bin/env bash
#
# The public page as it is published: static files that ask nothing of any
# other server.
#
# Cloudflare serves _site/ exactly as it is tracked, so nothing between the
# checkout and a visitor can add a missing file or repair a broken reference.
# These cases hold the tracked files to what the page states about itself: it
# runs no script, it loads every resource from its own directory, and every
# link inside the page lands somewhere. The last one holds the Wrangler
# configuration to publishing this directory and nothing more.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/jsonc.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/jsonc.sh"
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

# Wrangler publishes what its configuration points at, to whichever account
# it is signed in to. The tracked configuration therefore names this
# directory, no account, no Worker code, and no second public address.
test_wrangler_publishes_this_directory_and_names_no_account() {
  local config
  config=$(jsonc_to_json "$REPOSITORY_ROOT/wrangler.jsonc") \
    || scenario_fail 'wrangler.jsonc is not valid JSONC'

  assert_equal './_site' "$(jq -r '.assets.directory' <<<"$config")" \
    'published directory'
  assert_equal 'null' "$(jq -r '.account_id' <<<"$config")" 'account identifier'
  assert_equal 'null' "$(jq -r '.main' <<<"$config")" 'Worker entry point'
  assert_equal 'false' "$(jq -r '.preview_urls' <<<"$config")" 'preview URLs'
}

scenario_run 'the page runs no script' \
  test_the_page_runs_no_script
scenario_run 'every resource is a tracked file beside the page' \
  test_every_resource_is_a_tracked_file_beside_the_page
scenario_run 'every link inside the page has a target' \
  test_every_link_inside_the_page_has_a_target
scenario_run 'Wrangler publishes this directory and names no account' \
  test_wrangler_publishes_this_directory_and_names_no_account
scenario_finish
