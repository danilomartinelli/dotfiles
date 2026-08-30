#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/fixture.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/fixture.sh"
scenario_init dotfiles-openchamber-install-tests

CATALOG=$REPOSITORY_ROOT/openchamber/_settings.tsv

make_fixture() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/OpenChamber.app"

  # The installer merges real JSON and the assertions read it back, so this
  # fixture borrows the real jq rather than stubbing one that would have to
  # reimplement the merge it is meant to be checking.
  ln -s "$(command -v jq)" "$fixture/fake-bin/jq"

  printf '%s\n' "$fixture"
}

invoke_openchamber() {
  local fixture=$1
  shift
  fixture_run "$fixture" \
    OPENCHAMBER_APP="$fixture/OpenChamber.app" \
    "$@" \
    -- "$REPOSITORY_ROOT/openchamber/install.sh"
}

settings_path() {
  printf '%s\n' "$1/home/.config/openchamber/settings.json"
}

seed_settings() {
  mkdir -p "$(dirname -- "$(settings_path "$1")")"
  cat >"$(settings_path "$1")"
}

setting() {
  jq -r --arg key "$2" '.[$key] | tostring' "$(settings_path "$1")"
}

catalog_keys() {
  awk -F'\t' '!/^#/ && NF == 2 { print $1 }' "$CATALOG"
}

test_every_catalogued_key_is_written() {
  local fixture key
  fixture=$(make_fixture)
  invoke_openchamber "$fixture"

  while IFS= read -r key; do
    [ "$(setting "$fixture" "$key")" != null ] \
      || scenario_fail "catalogued key was not written: $key"
  done < <(catalog_keys)
}

test_untracked_keys_survive_the_merge() {
  local fixture
  fixture=$(make_fixture)
  seed_settings "$fixture" <<'JSON'
{
  "relayEncryptionKey": "relay-secret",
  "relaySigningKey": "signing-secret",
  "activeProjectId": "machine-state"
}
JSON
  invoke_openchamber "$fixture"

  # This is why settings.json is merged rather than linked: the file holds
  # secrets and per-machine state alongside the tracked preferences.
  assert_equal relay-secret "$(setting "$fixture" relayEncryptionKey)" \
    'the relay encryption key survived the merge'
  assert_equal signing-secret "$(setting "$fixture" relaySigningKey)" \
    'the relay signing key survived the merge'
  assert_equal machine-state "$(setting "$fixture" activeProjectId)" \
    'per-machine session state survived the merge'
}

test_checkout_placeholder_resolves_to_the_wrapper() {
  local fixture
  fixture=$(make_fixture)
  invoke_openchamber "$fixture"

  assert_equal "$REPOSITORY_ROOT/bin/opencode-profile" \
    "$(setting "$fixture" opencodeBinary)" \
    'the binary path resolved to the profile wrapper in this checkout'
}

test_a_tracked_value_replaces_a_stale_one() {
  local fixture
  fixture=$(make_fixture)
  seed_settings "$fixture" <<'JSON'
{ "themeId": "stale-theme" }
JSON
  invoke_openchamber "$fixture"

  assert_equal catppuccin-dark "$(setting "$fixture" themeId)" \
    'the catalogue overwrote the stale tracked value'
}

test_an_owned_object_is_replaced_whole() {
  local fixture
  fixture=$(make_fixture)
  seed_settings "$fixture" <<'JSON'
{ "notificationTemplates": { "retired": { "title": "gone" } } }
JSON
  invoke_openchamber "$fixture"

  # A deep merge would leave the retired subkey underneath, so the catalogue
  # could never remove one.
  assert_equal null \
    "$(jq -r '.notificationTemplates.retired // "null"' "$(settings_path "$fixture")")" \
    'a subkey the catalogue dropped did not survive'
  assert_equal 'Tool error' \
    "$(jq -r '.notificationTemplates.error.title' "$(settings_path "$fixture")")" \
    'the catalogued template replaced it'
}

test_a_missing_settings_file_is_created() {
  local fixture
  fixture=$(make_fixture)
  invoke_openchamber "$fixture"

  [ -f "$(settings_path "$fixture")" ] \
    || scenario_fail 'the installer did not create settings.json'
  assert_contains "$fixture/stdout.log" 'merged'
}

test_a_second_run_changes_nothing() {
  local fixture before
  fixture=$(make_fixture)
  invoke_openchamber "$fixture"
  before=$(cat "$(settings_path "$fixture")")

  invoke_openchamber "$fixture"

  assert_contains "$fixture/stdout.log" 'already match the catalog'
  assert_equal "$before" "$(cat "$(settings_path "$fixture")")" \
    'the second run left settings.json byte-identical'
}

test_a_missing_app_skips_the_topic() {
  local fixture
  fixture=$(make_fixture)
  rmdir "$fixture/OpenChamber.app"
  invoke_openchamber "$fixture"

  assert_contains "$fixture/stderr.log" 'OpenChamber not installed yet; skipping'
  assert_contains "$fixture/stderr.log" 'brew install --cask openchamber'
  [ ! -e "$(settings_path "$fixture")" ] \
    || scenario_fail 'the installer wrote settings for an absent app'
}

scenario_run 'every catalogued key reaches settings.json' test_every_catalogued_key_is_written
scenario_run 'secrets and session state survive the merge' test_untracked_keys_survive_the_merge
scenario_run 'the checkout placeholder resolves to the wrapper' test_checkout_placeholder_resolves_to_the_wrapper
scenario_run 'a tracked value replaces a stale one' test_a_tracked_value_replaces_a_stale_one
scenario_run 'an owned object is replaced whole' test_an_owned_object_is_replaced_whole
scenario_run 'a missing settings file is created' test_a_missing_settings_file_is_created
scenario_run 'a second run changes nothing' test_a_second_run_changes_nothing
scenario_run 'a missing app skips the topic' test_a_missing_app_skips_the_topic
scenario_finish
