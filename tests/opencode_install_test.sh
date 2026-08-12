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

test_env_defaults_to_opencode_home_and_preserves_override() {
  local home output

  home=$(scenario_tmpdir env)
  # shellcheck disable=SC2016 # Expanded by the nested Zsh, not this Bash test.
  output=$(env -u OPENCODE_CONFIG_DIR HOME="$home" /bin/zsh -c \
    'source "$1"; print -r -- "$OPENCODE_CONFIG_DIR"' zsh \
    "$REPOSITORY_ROOT/opencode/env.zsh") || return 1
  assert_equal "$home/.opencode" "$output" 'default OpenCode config directory'

  # shellcheck disable=SC2016 # Expanded by the nested Zsh, not this Bash test.
  output=$(env HOME="$home" XDG_CONFIG_HOME="$home/.config" \
    OPENCODE_CONFIG_DIR="$home/.config/opencode" \
    /bin/zsh -c 'source "$1"; print -r -- "$OPENCODE_CONFIG_DIR"' zsh \
    "$REPOSITORY_ROOT/opencode/env.zsh") || return 1
  assert_equal "$home/.opencode" "$output" 'legacy OpenCode config directory'

  # shellcheck disable=SC2016 # Expanded by the nested Zsh, not this Bash test.
  output=$(env HOME="$home" OPENCODE_CONFIG_DIR="$home/custom-opencode" \
    /bin/zsh -c 'source "$1"; print -r -- "$OPENCODE_CONFIG_DIR"' zsh \
    "$REPOSITORY_ROOT/opencode/env.zsh") || return 1
  assert_equal "$home/custom-opencode" "$output" 'OpenCode config override'
}

test_config_resolves_managed_instructions_through_config_dir() {
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc" \
    '"{env:OPENCODE_CONFIG_DIR}/tools/philosophy.md"'
  [[ -f $REPOSITORY_ROOT/opencode/opencode.symlink/tools/philosophy.md ]] \
    || scenario_fail 'managed philosophy instructions are missing'
}

test_installer_verifies_linked_payload_without_relinking() {
  local home fake_bin marker receipt receipt_hash

  home=$(scenario_tmpdir linked)
  fake_bin=$(make_fake_clis "$home")
  marker=$home/.opencode/managed-marker
  receipt=$home/.ocx/receipt.jsonc
  mkdir -p "$home/.opencode" "$home/.ocx"
  printf 'keep\n' >"$marker"
  scenario_write_file "$receipt" <<'EOF'
{
  "untouched": true,
  "opencode": {
    "instructions": ["./tools/philosophy.md"]
  }
}
EOF

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/stdout.log" "OpenCode config available at $home/.opencode"
  assert_contains "$home/stdout.log" 'ocx CLI available'
  assert_contains "$home/stdout.log" 'opencode CLI available'
  assert_contains "$home/stdout.log" 'Migrated OCX receipt instruction path'
  assert_contains "$marker" 'keep'
  assert_contains "$receipt" '"untouched": true'
  assert_contains "$receipt" '".opencode/tools/philosophy.md"'
  assert_not_contains "$receipt" '"./tools/philosophy.md"'
  [[ ! -e $home/.config/opencode ]] \
    || scenario_fail 'installer recreated the legacy XDG config directory'

  receipt_hash=$(shasum -a 256 "$receipt" | cut -d' ' -f1)
  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"
  assert_equal "$receipt_hash" \
    "$(shasum -a 256 "$receipt" | cut -d' ' -f1)" \
    'OCX receipt after idempotent reinstall'
  assert_not_contains "$home/stdout.log" 'Migrated OCX receipt instruction path'
}

test_installer_explains_missing_bootstrap_link() {
  local home fake_bin

  home=$(scenario_tmpdir missing)
  fake_bin=$(make_fake_clis "$home")

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/stderr.log" \
    "OpenCode config is not linked at $home/.opencode"
  assert_contains "$home/stderr.log" \
    'link opencode/opencode.symlink'
}

scenario_run 'OpenCode env defaults to ~/.opencode and preserves overrides' \
  test_env_defaults_to_opencode_home_and_preserves_override
scenario_run 'OpenCode instructions resolve through OPENCODE_CONFIG_DIR' \
  test_config_resolves_managed_instructions_through_config_dir
scenario_run 'OpenCode installer verifies the bootstrap-owned payload' \
  test_installer_verifies_linked_payload_without_relinking
scenario_run 'OpenCode installer explains a missing bootstrap link' \
  test_installer_explains_missing_bootstrap_link
scenario_finish
