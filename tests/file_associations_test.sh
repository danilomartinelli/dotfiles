#!/usr/bin/env bash
# shellcheck disable=SC2016 # Fixture commands and labels intentionally remain literal.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/fixture.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/fixture.sh"
scenario_init dotfiles-file-associations-tests

make_checkout() {
  local checkout file
  checkout=$(installer_fixture checkout)
  mkdir -p "$checkout/_scripts" "$checkout/sample"
  for file in installer-preamble.sh installer-output.sh catalog.sh \
    file-associations.sh file-associations-rules.sh; do
    cp "$REPOSITORY_ROOT/_scripts/$file" "$checkout/_scripts/$file"
  done
  printf '%s\n' "$checkout"
}

write_claim_installer() {
  local installer=$1
  shift

  scenario_write_executable "$installer" <<EOF
#!/bin/sh
set -eu
# shellcheck disable=SC1091
. "\$(CDPATH='' cd -P -- "\$(dirname -- "\$0")/../_scripts" && pwd)/installer-preamble.sh"
. "\$DOTFILES_ROOT/_scripts/file-associations.sh"
$*
EOF
}

# The catalog lives beside the installer, so a fixture topic dir is the whole
# setup: no path override exists, by design.
write_association_fixture() {
  local checkout=$1
  local catalog=$2
  local fake_bin=$checkout/fake-bin

  stub_duti "$fake_bin"

  printf '%s' "$catalog" >"$checkout/sample/_associations.tsv"
  write_claim_installer "$checkout/sample/install.sh" \
    'installer_claim_file_types Sample com.example.sample "sample associations set"'
}

write_claim_fixture() {
  local checkout=$1

  write_association_fixture "$checkout" "$(printf '%b\n' '.md\teditor\treport\t-')"
  write_claim_installer "$checkout/sample/install.sh" \
    'installer_claim_file_types Sample com.example.sample "sample associations set"
printf "continued\n"'
}

invoke_claim() {
  local checkout=$1
  shift
  fixture_run "$checkout" "$@" -- "$checkout/sample/install.sh"
}

test_associations_apply_every_row_with_its_role() {
  local checkout
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    '# comment line ignored' \
    '' \
    '.md\teditor\treport\t-' \
    'public.zip-archive\tviewer\treport\t.zip' \
    'com.adobe.pdf\teditor\tignore\t-')"

  invoke_claim "$checkout"

  assert_count "$checkout/events.log" 'duti -s com.example.sample' 3
  assert_contains "$checkout/events.log" '.md editor'
  assert_contains "$checkout/events.log" 'public.zip-archive viewer'
  assert_contains "$checkout/events.log" 'com.adobe.pdf editor'
  assert_before "$checkout/events.log" '.md editor' 'public.zip-archive viewer'
  assert_contains "$checkout/stdout.log" '✓ sample associations set'
  assert_not_contains "$checkout/stderr.log" 'Warning:'
}

test_associations_name_a_reported_failure_by_label() {
  local checkout
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    'public.zip-archive\tviewer\treport\t.zip' \
    '.md\teditor\treport\t-')"

  invoke_claim "$checkout" FAIL_DUTI=1 FAKE_DUTI_IDENTIFIERS=public.zip-archive

  # The label column carries the human name; a "-" falls back to the identifier.
  assert_contains "$checkout/stderr.log" \
    'Warning: Failed to set Sample as default for .zip'
  assert_contains "$checkout/stderr.log" \
    'Warning: Some Sample file associations could not be configured (1 failed)'
  assert_not_contains "$checkout/stdout.log" 'sample associations set'
}

test_associations_count_every_reported_failure() {
  local checkout
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    '.md\teditor\treport\t-' \
    '.rst\teditor\treport\t-' \
    '.txt\teditor\treport\t-')"

  invoke_claim "$checkout" FAIL_DUTI=1 FAKE_DUTI_IDENTIFIERS='.md .rst'

  # A count of 2 is what proves the loop does not run in a subshell, which is
  # why the catalog is read by redirection rather than through a pipe.
  assert_contains "$checkout/stderr.log" \
    'Warning: Some Sample file associations could not be configured (2 failed)'
  assert_contains "$checkout/stderr.log" 'default for .md'
  assert_contains "$checkout/stderr.log" 'default for .rst'
}

test_associations_swallow_a_best_effort_failure() {
  local checkout status
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    'public.source-code\teditor\tignore\t-' \
    '.md\teditor\treport\t-')"

  status=0
  invoke_claim "$checkout" FAIL_DUTI=1 \
    FAKE_DUTI_IDENTIFIERS=public.source-code || status=$?

  # Best-effort rows keep running under set -e and never reach the count.
  assert_equal 0 "$status" 'exit status when only a best-effort row fails'
  assert_contains "$checkout/events.log" '.md editor'
  assert_not_contains "$checkout/stderr.log" 'public.source-code'
  assert_contains "$checkout/stdout.log" '✓ sample associations set'
}

test_associations_fail_without_a_catalog() {
  local checkout status
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' '.md\teditor\treport\t-')"
  rm "$checkout/sample/_associations.tsv"

  status=0
  invoke_claim "$checkout" || status=$?
  assert_equal 1 "$status" 'exit status for a missing association catalog'
  assert_contains "$checkout/stderr.log" 'Error: association catalog not readable'
  assert_not_contains "$checkout/stdout.log" 'sample associations set'
}

# Every fault is reported by line before the first duti call, so a typo in the
# last row cannot leave the rows above it claimed and the step re-armed.
test_an_invalid_association_catalog_claims_nothing() {
  local catalog checkout status
  checkout=$(make_checkout)
  catalog=$checkout/sample/_associations.tsv
  write_association_fixture "$checkout" "$(printf '%b\n' \
    '.md\teditor\treport\t-' \
    '.rst\tediter\treport\t-' \
    '.txt\teditor\tigore\t-' \
    '.csv\teditor\treport' \
    '.md\teditor\tignore\t-')"

  status=0
  invoke_claim "$checkout" || status=$?
  # Defaulting a typo either way would decide silently whether a failure is
  # heard, so an unknown mode is a catalog bug rather than a tolerated value.
  assert_equal 1 "$status" 'exit status for an invalid association catalog'
  assert_contains "$checkout/stderr.log" "$catalog:2: unknown role 'editer'"
  assert_contains "$checkout/stderr.log" "$catalog:3: unknown failure mode 'igore'"
  assert_contains "$checkout/stderr.log" "$catalog:4: missing label"
  assert_contains "$checkout/stderr.log" "$catalog:5: duplicates line 1"
  assert_contains "$checkout/stderr.log" "Error: invalid association catalog: $catalog"
  assert_not_contains "$checkout/events.log" 'duti'
}

# The run-once key is derived from the topic directory, which is what stops a
# topic gating on one key and marking another.
test_claim_derives_its_key_from_the_topic() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"

  invoke_claim "$checkout"
  [[ -f $checkout/state/dotfiles/sample-associations-applied ]] \
    || scenario_fail 'claim did not record a marker keyed by the topic'
}

test_claim_applies_once_and_reports_the_marker() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"

  invoke_claim "$checkout"
  assert_contains "$checkout/stdout.log" '✓ sample associations set'
  assert_contains "$checkout/stdout.log" '✓ Sample configured'

  rm "$checkout/fake-bin/duti"
  # scenario_capture starts a fresh event log per run, so an empty one here is
  # the second run reasserting nothing, even when duti is no longer installed.
  invoke_claim "$checkout"
  assert_not_contains "$checkout/events.log" 'duti -s'
  assert_contains "$checkout/stdout.log" \
    'file associations already applied; run DOTFILES_RESET=sample-associations dot to reapply'
  assert_contains "$checkout/stdout.log" '✓ Sample configured'
  assert_contains "$checkout/stdout.log" 'continued'
  assert_empty "$checkout/stderr.log"
}

test_claim_reset_re_arms_the_step() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"

  invoke_claim "$checkout"
  invoke_claim "$checkout" DOTFILES_RESET=sample-associations
  assert_contains "$checkout/events.log" 'duti -s com.example.sample .md editor'
  assert_contains "$checkout/stdout.log" '✓ sample associations set'

  invoke_claim "$checkout" DOTFILES_RESET=all
  assert_contains "$checkout/events.log" 'duti -s com.example.sample .md editor'
}

# The catalog is read again only on a reset, so a row broken after the first
# claim would otherwise stay hidden behind the marker until then.
test_claim_reports_a_broken_catalog_after_it_applied() {
  local checkout status
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"
  invoke_claim "$checkout"

  printf '%b\n' '.md\teditor\tigore\t-' >"$checkout/sample/_associations.tsv"
  status=0
  invoke_claim "$checkout" || status=$?
  assert_equal 1 "$status" 'exit status for a broken catalog after the claim applied'
  assert_contains "$checkout/stderr.log" "unknown failure mode 'igore'"
  assert_not_contains "$checkout/stdout.log" 'already applied'
}

# A machine without duti has applied nothing and must stay armed for a retry.
test_claim_without_duti_leaves_the_step_armed() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"
  rm "$checkout/fake-bin/duti"

  invoke_claim "$checkout"
  assert_contains "$checkout/stderr.log" \
    'duti is required to set Sample as the default app for its declared file types'
  [[ ! -f $checkout/state/dotfiles/sample-associations-applied ]] \
    || scenario_fail 'a run without duti recorded the marker'
}

# Exercise the real Skim and Zed adapters with their tracked catalogs. Only
# their fixed application directory moves into the fixture; installer helpers,
# configuration linking, catalog rules, and the run-once lifecycle stay real.
test_topic_claims_its_catalog_once() {
  local topic=$1 app=$2 bundle=$3 identifier=$4
  local checkout
  checkout=$(make_checkout)
  mkdir -p "$checkout/$topic" "$checkout/home/Applications/$app.app"
  cp "$REPOSITORY_ROOT/$topic/_associations.tsv" "$checkout/$topic/"
  cp "$REPOSITORY_ROOT/_scripts/link-config" "$checkout/_scripts/"
  if [ "$topic" = zed ]; then
    cp "$REPOSITORY_ROOT/zed/settings.json" "$REPOSITORY_ROOT/zed/keymap.json" \
      "$checkout/zed/"
  fi
  sed 's|/Applications/|"$HOME"/Applications/|g' \
    "$REPOSITORY_ROOT/$topic/install.sh" >"$checkout/$topic/install.sh"
  chmod +x "$checkout/$topic/install.sh"
  stub_duti "$checkout/fake-bin"

  fixture_run "$checkout" -- "$checkout/$topic/install.sh"
  assert_contains "$checkout/events.log" "duti -s $bundle $identifier editor"
  assert_not_contains "$checkout/events.log" ' viewer'
  assert_not_contains "$checkout/events.log" ' all'
  assert_contains "$checkout/stdout.log" "$app configured"
  assert_empty "$checkout/stderr.log"

  fixture_run "$checkout" -- "$checkout/$topic/install.sh"
  assert_not_contains "$checkout/events.log" 'duti -s'
  assert_contains "$checkout/stdout.log" \
    "file associations already applied; run DOTFILES_RESET=$topic-associations dot to reapply"

  fixture_run "$checkout" DOTFILES_RESET="$topic-associations" \
    -- "$checkout/$topic/install.sh"
  assert_contains "$checkout/events.log" "duti -s $bundle $identifier editor"
}

scenario_run 'Skim claims its catalog once and reapplies on reset' \
  test_topic_claims_its_catalog_once skim Skim net.sourceforge.skim-app.skim .pdf
scenario_run 'Zed claims its catalog once and reapplies on reset' \
  test_topic_claims_its_catalog_once zed Zed dev.zed.Zed .html
scenario_run 'claim derives its run-once key from the topic' \
  test_claim_derives_its_key_from_the_topic
scenario_run 'claim applies once and reports the marker' \
  test_claim_applies_once_and_reports_the_marker
scenario_run 'DOTFILES_RESET re-arms a claimed catalog' \
  test_claim_reset_re_arms_the_step
scenario_run 'a claim without duti leaves the step armed' \
  test_claim_without_duti_leaves_the_step_armed
scenario_run 'a claim reports a broken catalog after it applied' \
  test_claim_reports_a_broken_catalog_after_it_applied
scenario_run 'associations apply every catalog row with its own role' \
  test_associations_apply_every_row_with_its_role
scenario_run 'a reported association failure is named by its label' \
  test_associations_name_a_reported_failure_by_label
scenario_run 'every reported association failure reaches the count' \
  test_associations_count_every_reported_failure
scenario_run 'a best-effort association failure is neither named nor counted' \
  test_associations_swallow_a_best_effort_failure
scenario_run 'a missing association catalog fails loudly' \
  test_associations_fail_without_a_catalog
scenario_run 'an invalid association catalog claims nothing' \
  test_an_invalid_association_catalog_claims_nothing
scenario_finish
