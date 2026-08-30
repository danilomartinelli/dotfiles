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
  mkdir -p "$fixture/fake-bin" "$fixture/Archiver.app/Contents"
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

invoke_archiver() {
  local fixture=$1
  scenario_capture "$fixture" env \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    ARCHIVER_APP="$fixture/Archiver.app" \
    PLIST_BUDDY_BIN="$fixture/fake-bin/PlistBuddy" \
    CODESIGN_BIN="$fixture/fake-bin/codesign" \
    LSREGISTER_BIN="$fixture/fake-bin/lsregister" \
    "$REPOSITORY_ROOT/archiver/install.sh"
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
scenario_run 'individual association failures are aggregated' test_individual_association_failures_are_aggregated
scenario_finish
