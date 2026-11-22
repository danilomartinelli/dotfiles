#!/usr/bin/env bash
#
# Secrets reach the project or the command that needs them and nothing else:
# provider keys copied from Bitwarden into encrypted stores and injected into
# one command, and project secrets loaded by direnv from an encrypted file.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/fixture.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/fixture.sh"
scenario_init dotfiles-provider-keys-tests

SYNC=$REPOSITORY_ROOT/bin/provider-keys-sync
WITH_KEYS=$REPOSITORY_ROOT/bin/with-provider-keys

# A home with an age identity, a vault holding one tool's note, and stand-ins
# for the tools around them. The fake sops marks each line instead of
# encrypting it, which is enough to tell a store from its plaintext.
new_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/home/.config/sops/age"
  printf 'AGE-SECRET-KEY-FIXTURE\n' >"$fixture/home/.config/sops/age/keys.txt"
  ln -s "$(command -v jq)" "$fixture/fake-bin/jq"

  scenario_write_file "$fixture/vault.json" <<'EOF'
[
  {"name": "dotfiles/provider-keys/opencode",
   "notes": "# rotated monthly\nFIXTURE_ALPHA_KEY=value with spaces\nFIXTURE_BETA_KEY=a=b$HOME"},
  {"name": "dotfiles/provider-keys-archive", "notes": "IGNORED=1"},
  {"name": "unrelated", "notes": "IGNORED=1"}
]
EOF
  scenario_write_executable "$fixture/fake-bin/bw" <<'EOF'
#!/bin/sh
printf 'bw %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
case $1 in
  status) printf '{"status":"%s"}\n' "${FAKE_BW_STATUS:-unlocked}" ;;
  sync) exit "${FAIL_BW_SYNC:-0}" ;;
  list) cat "$FAKE_BW_VAULT" ;;
esac
EOF
  scenario_write_executable "$fixture/fake-bin/age-keygen" <<'EOF'
#!/bin/sh
[ "$1" = -y ] && [ -f "$2" ] && printf 'age1fixturerecipient\nage1secondrecipient\n'
EOF
  scenario_write_executable "$fixture/fake-bin/sops" <<'EOF'
#!/bin/sh
[ "${FAIL_SOPS:-0}" = 0 ] || exit "$FAIL_SOPS"
operation=$1
for argument in "$@"; do
  last=$argument
  case $argument in age1*) printf 'recipient %s\n' "$argument" >>"$SCENARIO_EVENT_LOG" ;; esac
done
case $operation in
  encrypt) sed 's/^/sealed:/' "$last" ;;
  decrypt) sed -n 's/^sealed://p' "$last" ;;
esac
EOF
  printf '%s\n' "$fixture"
}

# Usage: run_sync <fixture> [KEY=value ...] [-- tool...]
run_sync() {
  local fixture=$1
  shift
  local -a overrides=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  [ "$#" -eq 0 ] || shift
  fixture_run "$fixture" FAKE_BW_VAULT="$fixture/vault.json" \
    SOPS_AGE_KEY_FILE="$fixture/home/.config/sops/age/keys.txt" \
    ${overrides[@]+"${overrides[@]}"} -- "$SYNC" "$@"
}

store_of() {
  printf '%s\n' "$1/home/.config/dotfiles/provider-keys/$2.env"
}

test_syncing_writes_an_encrypted_private_store_per_noted_tool() {
  local fixture
  fixture=$(new_fixture)
  run_sync "$fixture"

  assert_contains "$(store_of "$fixture" opencode)" 'sealed:FIXTURE_ALPHA_KEY=value with spaces'
  assert_mode "$(store_of "$fixture" opencode)" 600
  assert_mode "$fixture/home/.config/dotfiles/provider-keys" 700
  assert_contains "$fixture/events.log" 'recipient age1fixturerecipient,age1secondrecipient'
  [ ! -e "$(store_of "$fixture" opencode).tmp" ] || scenario_fail 'a staging file was left behind'
  [ "$(find "$fixture/home/.config/dotfiles/provider-keys" -type f | wc -l)" -eq 1 ] \
    || scenario_fail 'a note outside the prefix became a store'
}

test_syncing_prints_key_names_and_never_values() {
  local fixture
  fixture=$(new_fixture)
  run_sync "$fixture"

  assert_contains "$fixture/stdout.log" 'opencode: FIXTURE_ALPHA_KEY FIXTURE_BETA_KEY'
  assert_not_contains "$fixture/stdout.log" 'value with spaces'
  assert_not_contains "$fixture/stderr.log" 'value with spaces'
}

test_a_locked_vault_stops_the_sync_and_says_how_to_unlock_it() {
  local fixture
  fixture=$(new_fixture)

  assert_fails_with_status 1 run_sync "$fixture" FAKE_BW_STATUS=locked
  assert_contains "$fixture/stderr.log" 'the Bitwarden vault is locked'
  assert_contains "$fixture/stderr.log" 'bw unlock --raw'
  [ ! -e "$(store_of "$fixture" opencode)" ] || scenario_fail 'a store was written from a locked vault'
}

test_a_tool_without_a_note_is_an_error() {
  local fixture
  fixture=$(new_fixture)

  assert_fails_with_status 1 run_sync "$fixture" -- absent
  assert_contains "$fixture/stderr.log" 'no secure note named dotfiles/provider-keys/absent'
}

test_a_malformed_note_is_refused_without_quoting_it() {
  local fixture
  fixture=$(new_fixture)
  scenario_write_file "$fixture/vault.json" <<'EOF'
[{"name": "dotfiles/provider-keys/opencode", "notes": "GOOD=1\nnot a pair hunter2"}]
EOF

  assert_fails_with_status 1 run_sync "$fixture"
  assert_contains "$fixture/stderr.log" 'dotfiles/provider-keys/opencode line 2 is not KEY=value'
  assert_not_contains "$fixture/stderr.log" hunter2
  [ ! -e "$(store_of "$fixture" opencode)" ] || scenario_fail 'a malformed note was written'
}

test_a_failed_encryption_keeps_the_previous_store() {
  local fixture
  fixture=$(new_fixture)
  run_sync "$fixture"
  cp "$(store_of "$fixture" opencode)" "$fixture/before"

  assert_fails_with_status 1 run_sync "$fixture" FAIL_SOPS=1
  assert_equal "$(cat "$fixture/before")" "$(cat "$(store_of "$fixture" opencode)")" 'store'
  [ ! -e "$(store_of "$fixture" opencode).tmp" ] || scenario_fail 'a staging file was left behind'
}

test_a_missing_identity_names_the_command_that_creates_it() {
  local fixture
  fixture=$(new_fixture)
  rm "$fixture/home/.config/sops/age/keys.txt"

  assert_fails_with_status 1 run_sync "$fixture"
  assert_contains "$fixture/stderr.log" 'sops-key-create default'
  assert_not_contains "$fixture/events.log" 'bw list'
}

# The command prints what it was given and the two keys it should see.
write_probe() {
  scenario_write_executable "$1/fake-bin/probe" <<'EOF'
#!/bin/sh
printf 'alpha=[%s] beta=[%s] first=[%s] second=[%s]\n' \
  "${FIXTURE_ALPHA_KEY-unset}" "${FIXTURE_BETA_KEY-unset}" "$1" "$2"
EOF
}

test_the_command_receives_the_keys_and_its_own_arguments() {
  local fixture
  fixture=$(new_fixture)
  write_probe "$fixture"
  run_sync "$fixture"
  fixture_run "$fixture" -- "$WITH_KEYS" opencode -- probe 'two words' "it's"

  # shellcheck disable=SC2016 # The value holds a literal $HOME on purpose.
  assert_contains "$fixture/stdout.log" \
    'alpha=[value with spaces] beta=[a=b$HOME] first=[two words] second=[it'"'"'s]'
}

test_a_tool_without_a_store_runs_without_keys() {
  local fixture
  fixture=$(new_fixture)
  write_probe "$fixture"
  fixture_run "$fixture" -- "$WITH_KEYS" opencode -- probe a b

  assert_contains "$fixture/stdout.log" 'alpha=[unset] beta=[unset] first=[a] second=[b]'
  assert_contains "$fixture/stderr.log" 'no provider keys for opencode'
}

test_an_unreadable_store_stops_the_command() {
  local fixture
  fixture=$(new_fixture)
  write_probe "$fixture"
  run_sync "$fixture"

  assert_fails_with_status 1 fixture_run "$fixture" FAIL_SOPS=1 \
    -- "$WITH_KEYS" opencode -- probe a b
  assert_empty "$fixture/stdout.log"
  assert_contains "$fixture/stderr.log" 'could not decrypt'
}

test_the_command_exit_status_is_the_callers() {
  local fixture
  fixture=$(new_fixture)
  run_sync "$fixture"

  assert_fails_with_status 7 fixture_run "$fixture" -- "$WITH_KEYS" opencode -- sh -c 'exit 7'
  assert_fails_with_status 2 fixture_run "$fixture" -- "$WITH_KEYS" opencode probe
  assert_fails_with_status 2 fixture_run "$fixture" -- "$WITH_KEYS" '../etc' -- probe
}

# No shell exports a provider key: OpenCode and Zed both start OpenCode through
# the command, and the secret-free template no longer offers a place for one.
test_opencode_is_started_through_the_command_everywhere() {
  assert_contains "$REPOSITORY_ROOT/opencode/provider-keys.zsh" \
    'with-provider-keys opencode -- opencode "$@"'
  assert_contains "$REPOSITORY_ROOT/zed/settings.json" '"command": "with-provider-keys"'
  if grep -Eq '^#? *export [A-Z_]*(API_KEY|TOKEN)=' "$REPOSITORY_ROOT/.localrc.example"; then
    scenario_fail '.localrc.example still offers to export a credential'
  fi
}

# `use sops` as an .envrc calls it, with direnv's own helpers stood in for.
# Usage: use_sops_in <fixture> [file]
use_sops_in() {
  local fixture=$1
  shift
  scenario_write_executable "$fixture/fake-bin/direnv" <<'EOF'
#!/bin/sh
[ "$1 $2" = 'dotenv bash' ] && sed 's/^\([A-Z_]*\)=\(.*\)$/export \1="\2"/' "$3"
EOF
  (
    cd "$fixture/project" || exit 1
    # shellcheck disable=SC2016 # The child Bash expands these.
    fixture_run "$fixture" LIBRARY="$REPOSITORY_ROOT/direnv/lib/sops.sh" -- bash -c '
      watch_file() { printf "watching %s\n" "$1"; }
      log_error() { printf "%s\n" "$*" >&2; }
      source "$LIBRARY"
      use_sops "$@" || exit 1
      printf "token=[%s]\n" "${PROJECT_TOKEN-unset}"
    ' bash "$@"
  )
}

test_use_sops_loads_the_project_file_and_watches_it() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/project"
  printf 'sealed:PROJECT_TOKEN=from the project\n' >"$fixture/project/secrets.sops.env"
  use_sops_in "$fixture"

  assert_contains "$fixture/stdout.log" 'watching secrets.sops.env'
  assert_contains "$fixture/stdout.log" 'token=[from the project]'
}

test_use_sops_reports_a_missing_or_unreadable_file() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/project"

  assert_fails_with_status 1 use_sops_in "$fixture" other.env
  assert_contains "$fixture/stderr.log" 'use sops: other.env does not exist'

  printf 'sealed:PROJECT_TOKEN=x\n' >"$fixture/project/secrets.sops.env"
  assert_fails_with_status 1 use_sops_in "$fixture" FAIL_SOPS=1
}

scenario_run 'syncing writes an encrypted private store per noted tool' \
  test_syncing_writes_an_encrypted_private_store_per_noted_tool
scenario_run 'syncing prints key names and never values' \
  test_syncing_prints_key_names_and_never_values
scenario_run 'a locked vault stops the sync and says how to unlock it' \
  test_a_locked_vault_stops_the_sync_and_says_how_to_unlock_it
scenario_run 'a tool without a note is an error' \
  test_a_tool_without_a_note_is_an_error
scenario_run 'a malformed note is refused without quoting it' \
  test_a_malformed_note_is_refused_without_quoting_it
scenario_run 'a failed encryption keeps the previous store' \
  test_a_failed_encryption_keeps_the_previous_store
scenario_run 'a missing identity names the command that creates it' \
  test_a_missing_identity_names_the_command_that_creates_it
scenario_run 'the command receives the keys and its own arguments' \
  test_the_command_receives_the_keys_and_its_own_arguments
scenario_run 'a tool without a store runs without keys' \
  test_a_tool_without_a_store_runs_without_keys
scenario_run 'an unreadable store stops the command' \
  test_an_unreadable_store_stops_the_command
scenario_run "the command's exit status is the caller's" \
  test_the_command_exit_status_is_the_callers
scenario_run 'OpenCode is started through the command everywhere' \
  test_opencode_is_started_through_the_command_everywhere
scenario_run 'use sops loads the project file and watches it' \
  test_use_sops_loads_the_project_file_and_watches_it
scenario_run 'use sops reports a missing or unreadable file' \
  test_use_sops_reports_a_missing_or_unreadable_file

scenario_finish
