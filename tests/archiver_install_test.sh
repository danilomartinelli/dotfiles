#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-archiver-install-tests

make_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/fake-bin" "$fixture/home" "$fixture/Archiver.app/Contents"
  : >"$fixture/Archiver.app/Contents/Info.plist"

  scenario_write_executable "$fixture/fake-bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Darwin}"
EOF

  scenario_write_executable "$fixture/fake-bin/PlistBuddy" <<'EOF'
#!/bin/sh
[ "${ARCHIVER_PRESENT:-1}" -eq 1 ] || exit 1
printf '%s\n' com.incrediblebee.Archiver
EOF

  scenario_write_executable "$fixture/fake-bin/codesign" <<'EOF'
#!/bin/sh
printf 'codesign %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_CODESIGN:-0}"
EOF

  scenario_write_executable "$fixture/fake-bin/lsregister" <<'EOF'
#!/bin/sh
printf 'lsregister %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_LSREGISTER:-0}"
EOF

  scenario_write_executable "$fixture/fake-bin/duti" <<'EOF'
#!/bin/sh
printf 'duti %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
case "${FAIL_DUTI_UTI:-}" in
  "$3") exit 1 ;;
esac
EOF

  printf '%s\n' "$fixture"
}

# HOME and XDG_STATE_HOME are fixture-local because the associations are a
# run-once step: without them the marker would land in the real state directory
# and disarm both the next scenario and the next dot run.
invoke_archiver() {
  local fixture=$1
  shift
  scenario_capture "$fixture" env -u DOTFILES_RESET \
    HOME="$fixture/home" \
    XDG_STATE_HOME="$fixture/state" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    ARCHIVER_APP="$fixture/Archiver.app" \
    PLIST_BUDDY_BIN="$fixture/fake-bin/PlistBuddy" \
    CODESIGN_BIN="$fixture/fake-bin/codesign" \
    LSREGISTER_BIN="$fixture/fake-bin/lsregister" \
    "$@" \
    "$REPOSITORY_ROOT/archiver/install.sh"
}

archiver_marker() {
  printf '%s\n' "$1/state/dotfiles/archiver-associations-applied"
}

test_supported_types_use_viewer_role() {
  local fixture
  fixture=$(make_fixture)
  invoke_archiver "$fixture"

  assert_count "$fixture/events.log" 'duti -s com.incrediblebee.Archiver' 9
  assert_contains "$fixture/events.log" 'public.zip-archive viewer'
  assert_contains "$fixture/events.log" 'org.gnu.gnu-zip-tar-archive viewer'
  assert_not_contains "$fixture/events.log" ' editor'
  assert_not_contains "$fixture/events.log" 'zst'
  assert_not_contains "$fixture/events.log" 'lz4'
  assert_contains "$fixture/stdout.log" 'Archiver set as default for compressed files'
}

test_invalid_signature_is_reported_once() {
  local fixture
  fixture=$(make_fixture)
  export FAIL_CODESIGN=1
  invoke_archiver "$fixture"
  unset FAIL_CODESIGN

  assert_contains "$fixture/stderr.log" 'invalid code signature; skipping file associations'
  assert_not_contains "$fixture/events.log" 'lsregister'
  assert_not_contains "$fixture/events.log" 'duti '
}

test_registration_failure_skips_associations() {
  local fixture
  fixture=$(make_fixture)
  export FAIL_LSREGISTER=1
  invoke_archiver "$fixture"
  unset FAIL_LSREGISTER

  assert_contains "$fixture/stderr.log" 'macOS could not register Archiver'
  assert_not_contains "$fixture/events.log" 'duti '
}

test_missing_app_is_advisory() {
  local fixture
  fixture=$(make_fixture)
  export ARCHIVER_PRESENT=0
  invoke_archiver "$fixture"
  unset ARCHIVER_PRESENT

  assert_contains "$fixture/stderr.log" 'Archiver app not found'
  assert_not_contains "$fixture/events.log" 'codesign'
  assert_not_contains "$fixture/events.log" 'duti '
}

test_missing_duti_reports_the_missing_app_first() {
  local fixture
  fixture=$(make_fixture)
  rm "$fixture/fake-bin/duti"
  export ARCHIVER_PRESENT=0
  invoke_archiver "$fixture"
  unset ARCHIVER_PRESENT

  # Neither installed: the topic has nothing to do, and says so about the app
  # it configures rather than about a tool it never had a reason to reach for.
  assert_contains "$fixture/stderr.log" 'Archiver app not found'
  assert_not_contains "$fixture/stderr.log" 'duti'
  assert_not_contains "$fixture/events.log" 'codesign'
}

test_missing_duti_skips_the_associations() {
  local fixture
  fixture=$(make_fixture)
  rm "$fixture/fake-bin/duti"
  invoke_archiver "$fixture"

  assert_contains "$fixture/stderr.log" \
    'duti is required to set Archiver as the default app for its declared file types'
  assert_contains "$fixture/stderr.log" 'brew install duti'
  assert_not_contains "$fixture/stdout.log" 'Archiver set as default'
}

test_associations_apply_once() {
  local fixture
  fixture=$(make_fixture)
  invoke_archiver "$fixture"
  assert_contains "$fixture/stdout.log" 'Archiver set as default for compressed files'
  [[ -f $(archiver_marker "$fixture") ]] \
    || scenario_fail 'a successful apply did not record the run-once step'

  invoke_archiver "$fixture"
  assert_contains "$fixture/stdout.log" \
    'file associations already applied; run DOTFILES_RESET=archiver-associations dot to reapply'
  assert_contains "$fixture/stdout.log" 'Archiver configured'
  assert_not_contains "$fixture/events.log" 'duti '
}

test_reset_re_arms_the_associations() {
  local fixture
  fixture=$(make_fixture)
  invoke_archiver "$fixture"
  invoke_archiver "$fixture" DOTFILES_RESET=archiver-associations

  assert_count "$fixture/events.log" 'duti -s com.incrediblebee.Archiver' 9
}

test_a_bailed_run_leaves_the_step_armed() {
  local fixture
  fixture=$(make_fixture)

  # The marker sits below every gate, so a run that applied nothing cannot
  # record itself as applied and wedge the topic permanently.
  export FAIL_LSREGISTER=1
  invoke_archiver "$fixture"
  unset FAIL_LSREGISTER

  [[ ! -e $(archiver_marker "$fixture") ]] \
    || scenario_fail 'a run that skipped the associations recorded them as applied'

  invoke_archiver "$fixture"
  assert_count "$fixture/events.log" 'duti -s com.incrediblebee.Archiver' 9
}

test_individual_association_failures_are_aggregated() {
  local fixture
  fixture=$(make_fixture)
  export FAIL_DUTI_UTI=public.zip-archive
  invoke_archiver "$fixture"
  unset FAIL_DUTI_UTI

  assert_contains "$fixture/stderr.log" 'Failed to set Archiver as default for .zip'
  assert_contains "$fixture/stderr.log" \
    'Some Archiver file associations could not be configured (1 failed)'
}

scenario_run 'supported archive types use the viewer role' test_supported_types_use_viewer_role
scenario_run 'an invalid signature produces one actionable warning' test_invalid_signature_is_reported_once
scenario_run 'Launch Services registration failures skip associations' test_registration_failure_skips_associations
scenario_run 'a missing Archiver installation remains advisory' test_missing_app_is_advisory
scenario_run 'a missing duti reports the missing app first' test_missing_duti_reports_the_missing_app_first
scenario_run 'a missing duti skips the associations without failing' test_missing_duti_skips_the_associations
scenario_run 'associations apply once and report the marker' test_associations_apply_once
scenario_run 'DOTFILES_RESET re-arms the associations' test_reset_re_arms_the_associations
scenario_run 'a bailed run leaves the associations armed' test_a_bailed_run_leaves_the_step_armed
scenario_run 'individual association failures are aggregated' test_individual_association_failures_are_aggregated
scenario_finish
