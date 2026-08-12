#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-opencode-install-tests

make_fake_command() {
  local path=$1

  scenario_write_executable "$path" <<'EOF'
#!/bin/sh
exit 0
EOF
}

make_fake_clis() {
  local home=$1
  local fake_bin=$home/fake-bin

  mkdir -p "$fake_bin"
  make_fake_command "$fake_bin/ocx"
  make_fake_command "$fake_bin/opencode"
  printf '%s\n' "$fake_bin"
}

test_ocx_config_replaces_existing_directory_with_numbered_backup() {
  local home fake_bin

  home=$(scenario_tmpdir home)
  fake_bin=$(make_fake_clis "$home")
  mkdir -p "$fake_bin" "$home/.opencode" "$home/.opencode.backup"
  printf 'current config\n' >"$home/.opencode/current-marker"
  printf 'older backup\n' >"$home/.opencode.backup/backup-marker"

  scenario_capture "$home" env HOME="$home" \
    OPENCODE_CONFIG_DIR="$home/.config/opencode" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  [[ -L $home/.opencode ]] || scenario_fail 'OCX home config was not linked'
  assert_equal "$REPOSITORY_ROOT/opencode/extensions" \
    "$(readlink "$home/.opencode")" 'OCX config link target'
  assert_contains "$home/.opencode.backup/backup-marker" 'older backup'
  assert_contains "$home/.opencode.backup.1/current-marker" 'current config'
  assert_contains "$home/stdout.log" 'OpenCode OCX config linked'

  scenario_capture "$home" env HOME="$home" \
    OPENCODE_CONFIG_DIR="$home/.config/opencode" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"
  assert_contains "$home/stdout.log" 'OpenCode OCX config already linked'
  [[ ! -e $home/.opencode.backup.2 ]] \
    || scenario_fail 'idempotent reinstall created another backup'
}

test_rendered_config_updates_with_an_existing_backup() {
  local home fake_bin config expected

  home=$(scenario_tmpdir rendered)
  fake_bin=$(make_fake_clis "$home")
  config=$home/.config/opencode/opencode.json
  expected=$home/expected-opencode.json
  mkdir -p "$(dirname "$config")"
  printf 'stale rendered config\n' >"$config"
  printf 'older backup\n' >"$config.backup"
  sed "s|__DOTFILES_ROOT__|$REPOSITORY_ROOT|g" \
    "$REPOSITORY_ROOT/opencode/opencode.json" >"$expected"

  scenario_capture "$home" env HOME="$home" \
    OPENCODE_CONFIG_DIR="$home/.config/opencode" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  cmp -s "$expected" "$config" \
    || scenario_fail 'OpenCode config was not refreshed from the template'
  assert_contains "$config.backup" 'older backup'
  assert_contains "$config.backup.1" 'stale rendered config'
  assert_not_contains "$home/stderr.log" 'leaving OpenCode config untouched'
  assert_contains "$home/stdout.log" 'OpenCode config rendered'

  scenario_capture "$home" env HOME="$home" \
    OPENCODE_CONFIG_DIR="$home/.config/opencode" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"
  assert_contains "$home/stdout.log" 'OpenCode config already rendered'
  [[ ! -e $config.backup.2 ]] \
    || scenario_fail 'idempotent config render created another backup'
}

scenario_run 'OCX config survives an existing backup and links ~/.opencode' \
  test_ocx_config_replaces_existing_directory_with_numbered_backup
scenario_run 'rendered OpenCode config updates despite an existing backup' \
  test_rendered_config_updates_with_an_existing_backup
scenario_finish
