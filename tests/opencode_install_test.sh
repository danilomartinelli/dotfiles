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
  make_fake_command "$fake_bin/open-cursor"
  make_fake_command "$fake_bin/cursor-agent"
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

test_plugin_dependency_matches_pinned_opencode_version() {
  local opencode_version

  opencode_version=$(sed -n \
    's/^"npm:opencode-ai" = "\([^"]*\)"$/\1/p' \
    "$REPOSITORY_ROOT/mise/config.toml")
  [[ -n $opencode_version ]] \
    || scenario_fail 'pinned OpenCode version is missing from mise/config.toml'

  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/package.json" \
    "\"@opencode-ai/plugin\": \"$opencode_version\""
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/.gitignore" \
    'package-lock.json'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/.gitignore" \
    'bun.lock'
}

test_cursor_provider_uses_one_pinned_plugin_source() {
  local config
  local open_cursor_version

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  open_cursor_version=$(sed -n \
    's/^"npm:@rama_nigg\/open-cursor" = "\([^"]*\)"$/\1/p' \
    "$REPOSITORY_ROOT/mise/config.toml")
  [[ -n $open_cursor_version ]] \
    || scenario_fail 'pinned open-cursor version is missing from mise/config.toml'

  assert_contains "$config" \
    "\"@rama_nigg/open-cursor@$open_cursor_version\""
  assert_not_contains "$config" '"cursor-acp",'
  [[ ! -e $REPOSITORY_ROOT/opencode/opencode.symlink/plugins/cursor-acp.js ]] \
    || scenario_fail 'generated cursor-acp bundle would duplicate the npm plugin'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/package.json" \
    '"@ai-sdk/openai-compatible": "3.0.30"'
  assert_contains "$config" '"npm": "@ai-sdk/openai-compatible"'
}

test_installer_provisions_cursor_agent_and_requests_login() {
  local fake_bin
  local home

  home=$(scenario_tmpdir cursor-prerequisites)
  fake_bin=$home/fake-bin
  mkdir -p "$fake_bin"
  make_fake_command "$fake_bin/ocx"
  make_fake_command "$fake_bin/opencode"
  make_fake_command "$fake_bin/open-cursor"
  scenario_write_executable "$fake_bin/curl" <<'EOF'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    output=$2
    break
  fi
  shift
done
[ -n "${output:-}" ] || exit 2
cat >"$output" <<'INSTALLER'
#!/bin/sh
# Cursor Agent Installer
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/cursor-agent" <<'AGENT'
#!/bin/sh
exit 0
AGENT
chmod +x "$HOME/.local/bin/cursor-agent"
INSTALLER
EOF
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/events.log" \
    'curl -fsSL https://cursor.com/install -o'
  [[ -x $home/.local/bin/cursor-agent ]] \
    || scenario_fail 'Cursor Agent installer did not create the CLI'
  assert_contains "$home/stdout.log" 'cursor-agent CLI installed at'
  assert_contains "$home/stdout.log" \
    'Authenticate Cursor Agent once with: cursor-agent login'
}

test_installer_finds_open_cursor_through_mise() {
  local fake_bin
  local home

  home=$(scenario_tmpdir open-cursor-mise)
  fake_bin=$home/fake-bin
  mkdir -p "$fake_bin" "$home/mise-bin"
  make_fake_command "$fake_bin/ocx"
  make_fake_command "$fake_bin/opencode"
  make_fake_command "$fake_bin/cursor-agent"
  make_fake_command "$home/mise-bin/open-cursor"
  scenario_write_executable "$fake_bin/mise" <<EOF
#!/bin/sh
if [ "\$1" = which ] && [ "\$2" = open-cursor ]; then
  printf '%s\\n' "$home/mise-bin/open-cursor"
  exit 0
fi
exit 1
EOF
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/stdout.log" \
    "open-cursor CLI available at $home/mise-bin/open-cursor"
  assert_not_contains "$home/stdout.log" 'Install open-cursor with: mise install'
}

test_cursor_agent_download_failure_is_fatal() {
  local fake_bin
  local home

  home=$(scenario_tmpdir cursor-download-failure)
  fake_bin=$home/fake-bin
  mkdir -p "$fake_bin"
  make_fake_command "$fake_bin/ocx"
  make_fake_command "$fake_bin/opencode"
  make_fake_command "$fake_bin/open-cursor"
  scenario_write_executable "$fake_bin/curl" <<'EOF'
#!/bin/sh
exit 22
EOF
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"; then
    scenario_fail 'installer accepted a failed Cursor Agent download'
  fi

  assert_contains "$home/stderr.log" \
    'Failed to download the Cursor Agent installer'
}

test_agent_delivery_and_provider_permissions_are_explicit() {
  local config researcher workspace worktree

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  researcher=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/researcher.md
  workspace=$REPOSITORY_ROOT/opencode/opencode.symlink/plugins/workspace-plugin.ts
  worktree=$REPOSITORY_ROOT/opencode/opencode.symlink/plugins/worktree.ts

  assert_contains "$config" '"gh pr view*": "allow"'
  assert_contains "$config" '"glab mr view*": "allow"'
  assert_contains "$config" '"gh run list*": "allow"'
  assert_contains "$config" '"glab ci list*": "allow"'
  assert_contains "$config" '"gh api *": "allow"'
  assert_contains "$config" '"glab api *": "allow"'
  assert_contains "$researcher" '### GitHub and GitLab CLIs'

  assert_contains "$config" '"git commit*": "ask"'
  assert_contains "$config" '"git pull --ff-only*": "ask"'
  assert_contains "$config" '"git push*": "ask"'
  assert_contains "$config" '"git push --force*": "deny"'
  assert_contains "$config" '"worktree_delete": "deny"'
  assert_contains "$config" '"worktree_delete": "ask"'
  assert_contains "$workspace" 'All implementation MUST happen on a dedicated non-default branch'
  assert_contains "$workspace" 'Commit only when the user explicitly requests a commit.'
  assert_contains "$workspace" 'Push only when the user explicitly requests a push.'

  assert_contains "$worktree" 'The working tree must already be clean.'
  assert_contains "$worktree" 'Cannot delete a worktree with uncommitted changes.'
  assert_not_contains "$worktree" 'chore(worktree): session snapshot'
}

test_installer_verifies_linked_payload_without_relinking() {
  local home fake_bin receipt receipt_hash

  home=$(scenario_tmpdir linked)
  fake_bin=$(make_fake_clis "$home")
  receipt=$home/.ocx/receipt.jsonc
  mkdir -p "$home/.ocx"
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"
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
  assert_equal "$REPOSITORY_ROOT/opencode/opencode.symlink" \
    "$(readlink "$home/.opencode")" 'managed OpenCode link target'
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
  local home fake_bin status

  home=$(scenario_tmpdir missing)
  fake_bin=$(make_fake_clis "$home")

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"; then
    scenario_fail 'installer accepted a missing OpenCode config link'
  else
    status=$?
  fi

  assert_equal 1 "$status" 'missing OpenCode config link status'
  assert_contains "$home/stderr.log" \
    "OpenCode config is not linked at $home/.opencode"
  assert_contains "$home/stderr.log" \
    'link opencode/opencode.symlink'
}

test_installer_normalizes_legacy_xdg_environment() {
  local home fake_bin

  home=$(scenario_tmpdir legacy-xdg)
  fake_bin=$(make_fake_clis "$home")
  mkdir -p "$home/.config/opencode"
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"

  scenario_capture "$home" env HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    OPENCODE_CONFIG_DIR="$home/.config/opencode" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/stdout.log" \
    "OpenCode config available at $home/.opencode"
  [[ ! -L $home/.config/opencode ]] \
    || scenario_fail 'legacy XDG runtime directory was replaced'
}

test_installer_rejects_default_directory_conflict() {
  local home fake_bin status

  home=$(scenario_tmpdir directory-conflict)
  fake_bin=$(make_fake_clis "$home")
  mkdir -p "$home/.opencode"
  printf '%s\n' 'runtime content' >"$home/.opencode/package.json"

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"; then
    scenario_fail 'installer accepted a regular ~/.opencode directory'
  else
    status=$?
  fi

  assert_equal 1 "$status" 'OpenCode directory conflict status'
  assert_contains "$home/stderr.log" \
    "OpenCode config is not linked at $home/.opencode"
  assert_contains "$home/.opencode/package.json" 'runtime content'
}

scenario_run 'OpenCode env defaults to ~/.opencode and preserves overrides' \
  test_env_defaults_to_opencode_home_and_preserves_override
scenario_run 'OpenCode instructions resolve through OPENCODE_CONFIG_DIR' \
  test_config_resolves_managed_instructions_through_config_dir
scenario_run 'OpenCode plugin dependency follows the pinned CLI version' \
  test_plugin_dependency_matches_pinned_opencode_version
scenario_run 'Cursor provider has one pinned plugin source' \
  test_cursor_provider_uses_one_pinned_plugin_source
scenario_run 'OpenCode installer provisions Cursor Agent and requests login' \
  test_installer_provisions_cursor_agent_and_requests_login
scenario_run 'OpenCode installer finds open-cursor through Mise' \
  test_installer_finds_open_cursor_through_mise
scenario_run 'Cursor Agent download failures stop installation' \
  test_cursor_agent_download_failure_is_fatal
scenario_run 'OpenCode agents isolate branches and own explicit delivery' \
  test_agent_delivery_and_provider_permissions_are_explicit
scenario_run 'OpenCode installer verifies the bootstrap-owned payload' \
  test_installer_verifies_linked_payload_without_relinking
scenario_run 'OpenCode installer explains a missing bootstrap link' \
  test_installer_explains_missing_bootstrap_link
scenario_run 'OpenCode installer normalizes a legacy XDG environment' \
  test_installer_normalizes_legacy_xdg_environment
scenario_run 'OpenCode installer rejects a regular default config directory' \
  test_installer_rejects_default_directory_conflict
scenario_finish
