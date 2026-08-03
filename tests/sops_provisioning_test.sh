#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-sops-tests
TEST_ROOT=$SCENARIO_ROOT

make_home() {
  local test_home
  test_home=$(scenario_tmpdir home)
  printf '%s\n' "$test_home"
}

write_fake_commands() {
  local fake_bin=$1
  mkdir -p "$fake_bin"

  scenario_write_executable "$fake_bin/age-keygen" <<'EOF'
#!/bin/sh
printf '%s\n' call >> "$SCENARIO_EVENT_LOG"
key_path=
previous=
for argument in "$@"; do
  printf 'arg=%s\n' "$argument" >> "$SCENARIO_EVENT_LOG"
  if [ "$previous" = -o ]; then
    key_path=$argument
  fi
  previous=$argument
done

if [ "${AGE_KEYGEN_FAIL:-0}" -ne 0 ]; then
  exit "$AGE_KEYGEN_FAIL"
fi

[ -n "$key_path" ] || exit 98
cat > "$key_path" <<'KEY'
# created: 2026-01-01T00:00:00Z
# public key: age1fixturepublickey0000000000000000000000000000000000
AGE-SECRET-KEY-1FIXTURESECRETKEY000000000000000000000000000000
KEY
printf 'Public key: age1fixturepublickey0000000000000000000000000000000000\n' >&2
EOF
}

invoke_installer() {
  local test_home=$1
  scenario_capture "$test_home" env \
    HOME="$test_home" \
    XDG_CONFIG_HOME="$test_home/.config" \
    "$REPOSITORY_ROOT/sops/install.sh"
}

invoke_key_command() {
  local test_home=$1
  shift
  local fake_bin=$test_home/fake-bin

  mkdir -p "$fake_bin"
  if [[ ! -x $fake_bin/age-keygen ]]; then
    write_fake_commands "$fake_bin"
  fi

  (
    cd "$TEST_ROOT" || exit 1
    scenario_capture "$test_home" env \
      HOME="$test_home" \
      XDG_CONFIG_HOME="$test_home/.config" \
      PATH="$fake_bin:/usr/bin:/bin" \
      "$REPOSITORY_ROOT/bin/sops-key-create" "$@"
  )
}

test_installer_repairs_without_creating_keys() {
  local test_home age_dir

  test_home=$(make_home)
  age_dir=$test_home/.config/sops/age
  mkdir -p "$age_dir"
  printf '%s\n' 'AGE-SECRET-KEY-1EXISTING' >"$age_dir/keys.txt"
  printf '%s\n' 'age1existing' >"$age_dir/recipient.txt"
  chmod 777 "$age_dir" "$age_dir/keys.txt" "$age_dir/recipient.txt"

  invoke_installer "$test_home"

  assert_mode "$age_dir" 700
  assert_mode "$age_dir/keys.txt" 600
  assert_mode "$age_dir/recipient.txt" 644
  assert_contains "$test_home/stdout.log" 'default age identity already present'
  assert_contains "$test_home/stdout.log" 'sops configuration complete'
  assert_equal 'AGE-SECRET-KEY-1EXISTING' "$(cat "$age_dir/keys.txt")" 'key content preserved'
}

test_installer_hints_when_missing() {
  local test_home

  test_home=$(make_home)
  invoke_installer "$test_home"

  assert_mode "$test_home/.config/sops/age" 700
  assert_contains "$test_home/stdout.log" 'no default age identity yet'
  assert_contains "$test_home/stdout.log" 'sops-key-create default'
  [[ ! -e $test_home/.config/sops/age/keys.txt ]]
}

test_default_key_creation() {
  local test_home age_dir

  test_home=$(make_home)
  invoke_key_command "$test_home" default

  age_dir=$test_home/.config/sops/age
  assert_mode "$age_dir" 700
  assert_mode "$age_dir/keys.txt" 600
  assert_mode "$age_dir/recipient.txt" 644
  assert_contains "$age_dir/keys.txt" 'AGE-SECRET-KEY-1FIXTURE'
  assert_equal \
    'age1fixturepublickey0000000000000000000000000000000000' \
    "$(cat "$age_dir/recipient.txt")" \
    'recipient file'
  assert_contains "$test_home/stdout.log" 'created'
  assert_contains "$test_home/events.log" 'arg=-o'
}

test_role_paths_and_no_overwrite() {
  local test_home age_dir status

  test_home=$(make_home)
  invoke_key_command "$test_home" personal
  invoke_key_command "$test_home" work

  age_dir=$test_home/.config/sops/age
  [[ -f $age_dir/keys_personal.txt ]]
  [[ -f $age_dir/keys_work.txt ]]
  [[ -f $age_dir/recipient_personal.txt ]]
  [[ -f $age_dir/recipient_work.txt ]]

  status=0
  invoke_key_command "$test_home" personal || status=$?
  assert_equal 1 "$status" 'overwrite refused'
  assert_contains "$test_home/stderr.log" 'refusing to overwrite'
}

test_usage_and_missing_dependency() {
  local usage_home missing_home

  usage_home=$(make_home)
  assert_fails_with_status 2 invoke_key_command "$usage_home"
  assert_contains "$usage_home/stderr.log" 'Usage: sops-key-create'
  assert_fails_with_status 2 invoke_key_command "$usage_home" client
  invoke_key_command "$usage_home" --help
  assert_contains "$usage_home/stdout.log" 'Usage: sops-key-create'

  missing_home=$(make_home)
  mkdir -p "$missing_home/empty-bin"
  if scenario_capture "$missing_home" env \
    HOME="$missing_home" \
    XDG_CONFIG_HOME="$missing_home/.config" \
    PATH="$missing_home/empty-bin" \
    "$REPOSITORY_ROOT/sops/create-key" default; then
    return 1
  fi
  assert_contains "$missing_home/stderr.log" 'age-keygen is required'
}

scenario_run 'installer repairs permissions and never invents keys' test_installer_repairs_without_creating_keys
scenario_run 'installer hints when the default identity is missing' test_installer_hints_when_missing
scenario_run 'default age identity creation writes key and recipient' test_default_key_creation
scenario_run 'role paths are isolated and refuse overwrites' test_role_paths_and_no_overwrite
scenario_run 'usage and missing age-keygen are explicit' test_usage_and_missing_dependency
scenario_finish
