#!/usr/bin/env bash
#
# key-backup and key-restore: the identities this Mac holds go to Bitwarden
# and come back on a Mac that lacks them, and no key is ever overwritten.

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
scenario_init dotfiles-key-vault-tests

BACKUP=$REPOSITORY_ROOT/bin/key-backup
RESTORE=$REPOSITORY_ROOT/bin/key-restore

# A home and a fake Bitwarden whose vault is the JSON array in <fixture>/vault.
# The fake records every call's arguments, which must never hold key material.
new_fixture() {
  local fixture
  fixture=$(installer_fixture)
  ln -s "$(command -v jq)" "$fixture/fake-bin/jq"
  printf '[]\n' >"$fixture/vault"
  scenario_write_executable "$fixture/fake-bin/bw" <<'EOF'
#!/bin/sh
printf 'bw %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
case "$1 ${2-}" in
  'status ') printf '{"status":"%s"}\n' "${FAKE_BW_STATUS:-unlocked}" ;;
  'sync ') ;;
  'list items') cat "$FAKE_BW_VAULT" ;;
  'get template') printf '{"type":1,"name":"","notes":null,"login":{"username":null},"secureNote":null,"fields":[]}\n' ;;
  'encode ') base64 | tr -d '\n' ;;
  'create item')
    base64 -D >"$FAKE_BW_VAULT.item"
    jq --slurpfile item "$FAKE_BW_VAULT.item" \
      '. + [$item[0] + {id: "id-\(length + 1)"}]' "$FAKE_BW_VAULT" >"$FAKE_BW_VAULT.new"
    mv "$FAKE_BW_VAULT.new" "$FAKE_BW_VAULT"
    ;;
  'edit item')
    base64 -D >"$FAKE_BW_VAULT.item"
    jq --arg id "$3" --slurpfile item "$FAKE_BW_VAULT.item" \
      'map(if .id == $id then $item[0] + {id: $id} else . end)' "$FAKE_BW_VAULT" >"$FAKE_BW_VAULT.new"
    mv "$FAKE_BW_VAULT.new" "$FAKE_BW_VAULT"
    ;;
esac
EOF
  printf '%s\n' "$fixture"
}

# Usage: write_keys <home>: an SSH default pair and a default age identity.
write_keys() {
  mkdir -p "$1/.ssh" "$1/.config/sops/age"
  printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' 'fixture-ssh-private' \
    '-----END OPENSSH PRIVATE KEY-----' >"$1/.ssh/id_ed25519"
  printf 'ssh-ed25519 AAAAfixture fixture\n' >"$1/.ssh/id_ed25519.pub"
  printf '%s\n' '# created: 2026' 'AGE-SECRET-KEY-FIXTURE' >"$1/.config/sops/age/keys.txt"
  printf 'age1fixturerecipient\n' >"$1/.config/sops/age/recipient.txt"
}

# Usage: run_key_command <fixture> <command> [KEY=value ...] [-- key...]
run_key_command() {
  local fixture=$1 key_command=$2
  shift 2
  local -a overrides=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  [ "$#" -eq 0 ] || shift
  fixture_run "$fixture" FAKE_BW_VAULT="$fixture/vault" \
    ${overrides[@]+"${overrides[@]}"} -- "$key_command" "$@"
}

test_backup_stores_each_existing_key_as_a_secure_note() {
  local fixture
  fixture=$(new_fixture)
  write_keys "$fixture/home"
  run_key_command "$fixture" "$BACKUP"

  jq -e 'map(.name) == ["dotfiles/keys/ssh-default", "dotfiles/keys/age-default"]
    and all(.[]; .type == 2 and .secureNote == {"type": 0} and .login == null)
    and (.[0].notes | contains("fixture-ssh-private"))
    and .[0].fields == [{"name": "public", "value": "ssh-ed25519 AAAAfixture fixture", "type": 0}]
    and (.[1].notes | contains("AGE-SECRET-KEY-FIXTURE"))' "$fixture/vault" >/dev/null \
    || scenario_fail 'the vault does not hold the two keys as secure notes'
  assert_contains "$fixture/stdout.log" 'ssh-default stored'
}

test_key_material_never_appears_in_arguments_or_output() {
  local fixture log
  fixture=$(new_fixture)
  write_keys "$fixture/home"
  run_key_command "$fixture" "$BACKUP"

  for log in events.log stdout.log stderr.log; do
    assert_not_contains "$fixture/$log" fixture-ssh-private
    assert_not_contains "$fixture/$log" AGE-SECRET-KEY-FIXTURE
  done
}

test_a_second_backup_replaces_the_note_instead_of_adding_one() {
  local fixture
  fixture=$(new_fixture)
  write_keys "$fixture/home"
  run_key_command "$fixture" "$BACKUP"
  run_key_command "$fixture" "$BACKUP" -- age-default

  assert_equal 2 "$(jq length "$fixture/vault")" 'notes in the vault'
  assert_contains "$fixture/stdout.log" 'age-default replaced'
  assert_contains "$fixture/events.log" 'bw edit item id-2'
}

test_backup_needs_an_unlocked_vault_and_a_key() {
  local fixture
  fixture=$(new_fixture)

  assert_fails_with_status 1 run_key_command "$fixture" "$BACKUP"
  assert_contains "$fixture/stderr.log" 'no key exists on this Mac to store'
  assert_fails_with_status 1 run_key_command "$fixture" "$BACKUP" -- ssh-work
  assert_contains "$fixture/stderr.log" 'ssh-work does not exist'

  write_keys "$fixture/home"
  assert_fails_with_status 1 run_key_command "$fixture" "$BACKUP" FAKE_BW_STATUS=locked
  assert_contains "$fixture/stderr.log" 'the Bitwarden vault is locked'
  assert_equal 0 "$(jq length "$fixture/vault")" 'notes written from a locked vault'
}

# Back the keys up from one home and restore them into an empty one.
test_restore_returns_the_keys_to_a_mac_that_lacks_them() {
  local fixture
  fixture=$(new_fixture)
  write_keys "$fixture/home"
  run_key_command "$fixture" "$BACKUP"
  mv "$fixture/home" "$fixture/old-home"
  mkdir "$fixture/home"
  run_key_command "$fixture" "$RESTORE"

  assert_equal "$(cat "$fixture/old-home/.ssh/id_ed25519")" \
    "$(cat "$fixture/home/.ssh/id_ed25519")" 'SSH private key'
  assert_equal "$(cat "$fixture/old-home/.ssh/id_ed25519.pub")" \
    "$(cat "$fixture/home/.ssh/id_ed25519.pub")" 'SSH public key'
  assert_equal "$(cat "$fixture/old-home/.config/sops/age/keys.txt")" \
    "$(cat "$fixture/home/.config/sops/age/keys.txt")" 'age identity'
  assert_equal age1fixturerecipient \
    "$(cat "$fixture/home/.config/sops/age/recipient.txt")" 'age recipient'
  assert_mode "$fixture/home/.ssh/id_ed25519" 600
  assert_mode "$fixture/home/.ssh/id_ed25519.pub" 644
  assert_mode "$fixture/home/.ssh" 700
  assert_mode "$fixture/home/.config/sops/age/keys.txt" 600
  assert_not_contains "$fixture/stdout.log" fixture-ssh-private
}

test_restore_never_overwrites_a_key() {
  local fixture
  fixture=$(new_fixture)
  write_keys "$fixture/home"
  run_key_command "$fixture" "$BACKUP"
  printf 'the key this Mac already has\n' >"$fixture/home/.ssh/id_ed25519"
  rm "$fixture/home/.config/sops/age/keys.txt"

  run_key_command "$fixture" "$RESTORE"
  assert_contains "$fixture/stdout.log" 'ssh-default already exists; left alone'
  assert_contains "$fixture/stdout.log" 'age-default restored'
  assert_equal 'the key this Mac already has' "$(cat "$fixture/home/.ssh/id_ed25519")" \
    'existing SSH key'

  : >"$fixture/events.log"
  assert_fails_with_status 1 run_key_command "$fixture" "$RESTORE" -- ssh-default
  assert_contains "$fixture/stderr.log" 'refusing to overwrite existing key material'
  assert_empty "$fixture/events.log"
}

test_restore_reports_a_key_with_no_backup() {
  local fixture
  fixture=$(new_fixture)

  run_key_command "$fixture" "$RESTORE"
  assert_contains "$fixture/stdout.log" 'nothing to restore'
  assert_fails_with_status 1 run_key_command "$fixture" "$RESTORE" -- age-work
  assert_contains "$fixture/stderr.log" 'no note named dotfiles/keys/age-work'
}

test_both_commands_reject_an_unknown_key() {
  local fixture
  fixture=$(new_fixture)

  assert_fails_with_status 2 run_key_command "$fixture" "$BACKUP" -- gpg-default
  assert_fails_with_status 2 run_key_command "$fixture" "$RESTORE" -- ../../etc/passwd
  assert_contains "$fixture/stderr.log" 'unknown key: ../../etc/passwd'
  assert_empty "$fixture/events.log"
}

scenario_run 'backup stores each existing key as a secure note' \
  test_backup_stores_each_existing_key_as_a_secure_note
scenario_run 'key material never appears in arguments or output' \
  test_key_material_never_appears_in_arguments_or_output
scenario_run 'a second backup replaces the note instead of adding one' \
  test_a_second_backup_replaces_the_note_instead_of_adding_one
scenario_run 'backup needs an unlocked vault and a key' \
  test_backup_needs_an_unlocked_vault_and_a_key
scenario_run 'restore returns the keys to a Mac that lacks them' \
  test_restore_returns_the_keys_to_a_mac_that_lacks_them
scenario_run 'restore never overwrites a key' \
  test_restore_never_overwrites_a_key
scenario_run 'restore reports a key with no backup' \
  test_restore_reports_a_key_with_no_backup
scenario_run 'both commands reject an unknown key' \
  test_both_commands_reject_an_unknown_key

scenario_finish
