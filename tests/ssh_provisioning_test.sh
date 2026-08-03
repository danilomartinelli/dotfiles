#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-ssh-tests
TEST_ROOT=$SCENARIO_ROOT

make_home() {
  local test_home
  test_home=$(scenario_tmpdir home)
  printf '%s\n' "$test_home"
}

write_fake_commands() {
  local fake_bin=$1
  mkdir -p "$fake_bin"

  scenario_write_executable "$fake_bin/ssh-keygen" <<'EOF'
#!/bin/sh
printf '%s\n' call >> "$SCENARIO_EVENT_LOG"
key_path=
previous=
for argument in "$@"; do
  printf 'arg=%s\n' "$argument" >> "$SCENARIO_EVENT_LOG"
  if [ "$previous" = -f ]; then
    key_path=$argument
  fi
  previous=$argument
done

if [ "${SSH_KEYGEN_FAIL:-0}" -ne 0 ]; then
  exit "$SSH_KEYGEN_FAIL"
fi

[ -n "$key_path" ] || exit 98
: > "$key_path"
: > "$key_path.pub"
chmod 777 "$key_path" "$key_path.pub"
EOF

  scenario_write_executable "$fake_bin/git" <<'EOF'
#!/bin/sh
if [ "${SSH_TEST_NO_EMAIL:-0}" -ne 0 ]; then
  exit 1
fi
if [ "$*" = 'config --global user.email' ]; then
  printf '%s\n' 'keys@example.com'
  exit 0
fi
exit 1
EOF

  scenario_write_executable "$fake_bin/hostname" <<'EOF'
#!/bin/sh
printf '%s\n' fixture-host
EOF
}

invoke_installer() {
  local test_home=$1
  scenario_capture "$test_home" env \
    HOME="$test_home" \
    "$REPOSITORY_ROOT/ssh/install.sh"
}

invoke_key_command() {
  local test_home=$1
  shift
  local fake_bin=$test_home/fake-bin

  mkdir -p "$fake_bin"
  if [[ ! -x $fake_bin/ssh-keygen ]]; then
    write_fake_commands "$fake_bin"
  fi

  (
    cd "$TEST_ROOT" || exit 1
    scenario_capture "$test_home" env \
      HOME="$test_home" \
      PATH="$fake_bin:/usr/bin:/bin" \
      "$REPOSITORY_ROOT/bin/ssh-key-create" "$@"
  )
}

test_fresh_and_idempotent_provisioning() {
  local test_home config_target

  test_home=$(make_home)
  invoke_installer "$test_home"

  [[ -L $test_home/.ssh/config ]]
  config_target=$(readlink "$test_home/.ssh/config")
  assert_equal "$REPOSITORY_ROOT/ssh/config" "$config_target" 'managed config target'
  cmp "$REPOSITORY_ROOT/ssh/config_local.example" "$test_home/.ssh/config_local"
  assert_mode "$test_home/.ssh" 700
  assert_mode "$test_home/.ssh/config_local" 600
  assert_contains "$test_home/stdout.log" 'ssh configuration complete'

  printf '%s\n' '# preserved local entry' >> "$test_home/.ssh/config_local"
  : > "$test_home/.ssh/id_ed25519"
  : > "$test_home/.ssh/id_ed25519.pub"
  chmod 777 "$test_home/.ssh/config_local" "$test_home/.ssh/id_ed25519" "$test_home/.ssh/id_ed25519.pub"

  invoke_installer "$test_home"

  assert_contains "$test_home/.ssh/config_local" '# preserved local entry'
  assert_contains "$test_home/stdout.log" 'config already linked'
  assert_mode "$test_home/.ssh/config_local" 600
  assert_mode "$test_home/.ssh/id_ed25519" 600
  assert_mode "$test_home/.ssh/id_ed25519.pub" 644
  [[ ! -e $test_home/.ssh/config.backup ]]
}

test_collision_safe_config_backup() {
  local test_home

  test_home=$(make_home)
  mkdir -p "$test_home/.ssh"
  printf '%s\n' 'existing backup' > "$test_home/.ssh/config.backup"
  printf '%s\n' 'original config' > "$test_home/.ssh/config"

  invoke_installer "$test_home"

  [[ -L $test_home/.ssh/config ]]
  assert_contains "$test_home/.ssh/config.backup" 'existing backup'
  assert_contains "$test_home/.ssh/config.backup.1" 'original config'
  assert_contains "$test_home/stdout.log" "$test_home/.ssh/config.backup.1"

  test_home=$(make_home)
  mkdir -p "$test_home/.ssh"
  ln -s missing-config "$test_home/.ssh/config"
  invoke_installer "$test_home"
  [[ -L $test_home/.ssh/config.backup ]]
  assert_equal missing-config "$(readlink "$test_home/.ssh/config.backup")" 'broken config backup target'
  assert_equal "$REPOSITORY_ROOT/ssh/config" "$(readlink "$test_home/.ssh/config")" 'replacement config target'
}

test_installer_does_not_consume_stdin() {
  local test_home stdin_value

  test_home=$(make_home)
  printf '%s\n' ssh-stdin-sentinel > "$test_home/stdin"

  exec 3< "$test_home/stdin"
  scenario_capture "$test_home" env \
    HOME="$test_home" \
    "$REPOSITORY_ROOT/ssh/install.sh" <&3
  stdin_value=
  read -r stdin_value <&3
  exec 3<&-

  assert_equal ssh-stdin-sentinel "$stdin_value" 'installer stdin'
}

test_invalid_local_config_stops_without_replacement() {
  local test_home

  test_home=$(make_home)
  mkdir -p "$test_home/.ssh/config_local"

  if invoke_installer "$test_home"; then
    return 1
  fi

  [[ -d $test_home/.ssh/config_local ]]
  assert_contains "$test_home/stderr.log" 'must be a regular file or a symlink to one'
}

test_role_and_type_mappings() {
  local role flag key_type key_name comment test_host test_home

  while IFS='|' read -r role flag key_type key_name comment test_host; do
    test_home=$(make_home)
    invoke_key_command "$test_home" "$role" ${flag:+"$flag"}

    [[ -f $test_home/.ssh/$key_name ]]
    [[ -f $test_home/.ssh/$key_name.pub ]]
    assert_mode "$test_home/.ssh" 700
    assert_mode "$test_home/.ssh/$key_name" 600
    assert_mode "$test_home/.ssh/$key_name.pub" 644
    assert_contains "$test_home/events.log" 'arg=-t'
    assert_contains "$test_home/events.log" "arg=$key_type"
    assert_contains "$test_home/events.log" "arg=$test_home/.ssh/$key_name"
    assert_contains "$test_home/events.log" "arg=$comment"
    assert_contains "$test_home/stdout.log" "Public key: $test_home/.ssh/$key_name.pub"
    assert_contains "$test_home/stdout.log" "ssh -T $test_host"

    if [[ $key_type == rsa ]]; then
      assert_contains "$test_home/events.log" 'arg=-b'
      assert_contains "$test_home/events.log" 'arg=4096'
    else
      assert_not_contains "$test_home/events.log" 'arg=-b'
    fi
  done <<'EOF'
default||ed25519|id_ed25519|keys@example.com|github.com
personal||ed25519|id_ed25519_personal|keys@example.com (personal)|github-personal
work||ed25519|id_ed25519_work|keys@example.com (work)|github-work
default|--rsa|rsa|id_rsa|keys@example.com|github.com
personal|--rsa|rsa|id_rsa_personal|keys@example.com (personal)|github-personal
work|--rsa|rsa|id_rsa_work|keys@example.com (work)|github-work
EOF
}

test_existing_keys_are_never_overwritten() {
  local private_home public_home

  private_home=$(make_home)
  mkdir -p "$private_home/.ssh"
  printf '%s\n' private-material > "$private_home/.ssh/id_ed25519_personal"
  assert_fails_with_status 1 invoke_key_command "$private_home" personal
  assert_contains "$private_home/.ssh/id_ed25519_personal" private-material
  assert_not_contains "$private_home/events.log" call
  assert_contains "$private_home/stderr.log" 'refusing to overwrite existing key material'

  public_home=$(make_home)
  mkdir -p "$public_home/.ssh"
  printf '%s\n' public-material > "$public_home/.ssh/id_rsa_work.pub"
  assert_fails_with_status 1 invoke_key_command "$public_home" work --rsa
  assert_contains "$public_home/.ssh/id_rsa_work.pub" public-material
  assert_not_contains "$public_home/events.log" call
}

test_usage_dependency_fallback_and_failure() {
  local usage_home missing_home fallback_home failure_home status

  usage_home=$(make_home)
  assert_fails_with_status 2 invoke_key_command "$usage_home"
  assert_contains "$usage_home/stderr.log" 'Usage: ssh-key-create'
  assert_fails_with_status 2 invoke_key_command "$usage_home" client
  assert_fails_with_status 2 invoke_key_command "$usage_home" default --dsa
  invoke_key_command "$usage_home" --help
  assert_contains "$usage_home/stdout.log" 'Usage: ssh-key-create'

  missing_home=$(make_home)
  mkdir -p "$missing_home/empty-bin"
  if scenario_capture "$missing_home" env \
      HOME="$missing_home" \
      PATH="$missing_home/empty-bin" \
      "$REPOSITORY_ROOT/ssh/create-key" default; then
    return 1
  fi
  assert_contains "$missing_home/stderr.log" 'ssh-keygen is required'

  fallback_home=$(make_home)
  write_fake_commands "$fallback_home/fake-bin"
  (
    cd "$TEST_ROOT" || exit 1
    scenario_capture "$fallback_home" env \
      HOME="$fallback_home" \
      USER=fixture-user \
      PATH="$fallback_home/fake-bin:/usr/bin:/bin" \
      SSH_TEST_NO_EMAIL=1 \
      "$REPOSITORY_ROOT/bin/ssh-key-create" default
  )
  assert_contains "$fallback_home/events.log" 'arg=fixture-user@fixture-host'

  failure_home=$(make_home)
  write_fake_commands "$failure_home/fake-bin"
  if (
    cd "$TEST_ROOT" || exit 1
    scenario_capture "$failure_home" env \
      HOME="$failure_home" \
      PATH="$failure_home/fake-bin:/usr/bin:/bin" \
      SSH_KEYGEN_FAIL=7 \
      "$REPOSITORY_ROOT/bin/ssh-key-create" work
  ); then
    return 1
  else
    status=$?
  fi
  [[ $status -eq 7 ]]
  assert_contains "$failure_home/stderr.log" 'ssh-keygen failed'
  assert_not_contains "$failure_home/stdout.log" '✓ created'
}

scenario_run 'automatic provisioning is fresh-home safe and idempotent' test_fresh_and_idempotent_provisioning
scenario_run 'config conflicts receive collision-safe backups' test_collision_safe_config_backup
scenario_run 'automatic provisioning does not consume stdin' test_installer_does_not_consume_stdin
scenario_run 'invalid local config paths fail without replacement' test_invalid_local_config_stops_without_replacement
scenario_run 'all credential roles and key types map correctly' test_role_and_type_mappings
scenario_run 'existing key material is never overwritten' test_existing_keys_are_never_overwritten
scenario_run 'credential usage, dependencies, fallback, and failures are explicit' test_usage_dependency_fallback_and_failure
scenario_finish
