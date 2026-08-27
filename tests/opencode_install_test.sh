#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-opencode-install-tests

make_fake_clis() {
  local home=$1
  local fake_bin=$home/fake-bin

  mkdir -p "$fake_bin"

  scenario_write_executable "$fake_bin/uname" <<'EOF'
#!/bin/sh
printf 'Darwin\n'
EOF

  scenario_write_executable "$fake_bin/opencode" <<'EOF'
#!/bin/sh
printf 'native opencode %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  scenario_write_executable "$fake_bin/ocx" <<'EOF'
#!/bin/sh

config_dir=$HOME/.config/opencode
printf 'ocx %s\n' "$*" >>"$SCENARIO_EVENT_LOG"

case "$1 $2" in
  'init --global')
    mkdir -p "$config_dir/profiles/default"
    [ -e "$config_dir/ocx.jsonc" ] \
      || printf '{}\n' >"$config_dir/ocx.jsonc"
    ;;
  'add kdco/workspace')
    for entry in agents commands skills tools; do
      [ -e "$config_dir/$entry" ] || mkdir -p "$config_dir/$entry"
    done
		[ -e "$config_dir/opencode.jsonc" ] \
			|| printf '{}\n' >"$config_dir/opencode.jsonc"
		mkdir -p "$config_dir/.ocx" "$config_dir/plugins"
		printf '{"installed":{"https://registry.kdco.dev::kdco/workspace@sha256:test":{}}}\n' \
			>"$config_dir/.ocx/receipt.jsonc"
    printf 'runtime plugin\n' >"$config_dir/plugins/workspace.ts"
    printf '{"dependencies":{}}\n' >"$config_dir/package.json"
    printf 'node_modules\n' >"$config_dir/.gitignore"
    ;;
  'profile remove')
    rm -rf "$config_dir/profiles/$3"
    ;;
  'profile add')
    if [ "${4:-}" = '--clone' ] && [ ! -e "$config_dir/profiles/${5:-}" ]; then
      printf 'clone source missing: %s\n' "${5:-}" >&2
      exit 1
    fi
    mkdir -p "$config_dir/profiles/$3"
    printf 'generated profile\n' >"$config_dir/profiles/$3/generated"
    ;;
esac
EOF

  printf '%s\n' "$fake_bin"
}

assert_link_target() {
  local expected=$1
  local link=$2
  local description=$3

  [[ -L $link ]] || scenario_fail "$description is not a symbolic link"
  assert_equal "$expected" "$(readlink "$link")" "$description target"
}

jsonc_to_json() {
  yq -p json -o json '.' "$1"
}

test_shell_uses_regular_ocx_profile_and_shortcuts() {
  local fake_bin home output

  home=$(scenario_tmpdir shell)
  fake_bin=$(make_fake_clis "$home")

  # shellcheck disable=SC2016 # Expanded by the nested Zsh.
  output=$(env HOME="$home" /bin/zsh -f -c \
    'source "$1"; print -r -- "$OCX_PROFILE|$OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS|$OPENCODE_EXPERIMENTAL_WORKSPACES|$OPENCODE_DISABLE_PROJECT_CONFIG|$OPENCODE_DISABLE_EXTERNAL_SKILLS|$OPENCODE_DISABLE_CLAUDE_CODE_SKILLS"' \
    zsh "$REPOSITORY_ROOT/opencode/env.zsh") || return 1

  assert_equal 'regular|true|true|true|true|true' "$output" \
    'OpenCode shell environment'

  # shellcheck disable=SC2016 # Expanded by the nested Zsh.
  scenario_capture "$home" env HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" /bin/zsh -f -c \
    'source "$1"; for shortcut in opencode oc oc:boost oc:regular oc:go; do eval "$shortcut"; done' \
    zsh "$REPOSITORY_ROOT/opencode/aliases.zsh"

  assert_count "$home/events.log" 'ocx opencode' 5
  assert_contains "$home/events.log" 'ocx opencode -p boost'
  assert_contains "$home/events.log" 'ocx opencode -p regular'
  assert_contains "$home/events.log" 'ocx opencode -p go'
  assert_not_contains "$home/events.log" 'native opencode'
}

test_managed_payload_is_complete_and_runtime_payload_is_excluded() {
  local jsonc_path managed_path
  local -a managed_paths

  managed_paths=(
    agents/coder.md
    agents/researcher.md
    agents/reviewer.md
    agents/scribe.md
    commands/review.md
    skills/code-philosophy/SKILL.md
    skills/code-review/SKILL.md
    skills/frontend-philosophy/SKILL.md
    skills/plan-protocol/SKILL.md
    skills/plan-review/SKILL.md
    tools/philosophy.md
    ocx.jsonc
    opencode.jsonc
    tui.jsonc
    profiles/boost/AGENTS.md
    profiles/boost/ocx.jsonc
    profiles/boost/opencode.jsonc
    profiles/regular/AGENTS.md
    profiles/regular/ocx.jsonc
    profiles/regular/opencode.jsonc
    profiles/go/AGENTS.md
    profiles/go/ocx.jsonc
    profiles/go/opencode.jsonc
  )

  for managed_path in "${managed_paths[@]}"; do
    [[ -f $REPOSITORY_ROOT/opencode/$managed_path ]] \
      || scenario_fail "managed OpenCode payload is missing: $managed_path"
  done

  while IFS= read -r jsonc_path; do
    jsonc_to_json "$jsonc_path" >/dev/null \
      || scenario_fail "OpenCode JSONC is invalid: ${jsonc_path#"$REPOSITORY_ROOT/"}"
  done < <(find "$REPOSITORY_ROOT/opencode" -type f -name '*.jsonc' -print | sort)

  for managed_path in plugins .ocx package.json .gitignore; do
    [[ ! -e $REPOSITORY_ROOT/opencode/$managed_path ]] \
      || scenario_fail "runtime or legacy OpenCode payload is versioned: $managed_path"
  done
}

test_tui_matches_terminal_theme_and_interaction_defaults() {
  local tui_config

  tui_config=$REPOSITORY_ROOT/opencode/tui.jsonc

  jsonc_to_json "$tui_config" | jq -e '
		."$schema" == "https://opencode.ai/tui.json" and
		.theme == "catppuccin-macchiato" and
		.leader_timeout == 2000 and
		.keybinds == {
			"leader": "ctrl+x",
			"command_list": "ctrl+p"
		} and
		.scroll_speed == 3 and
		.scroll_acceleration == {"enabled": true} and
		.diff_style == "auto" and
		.cursor == {"style": "block", "blinking": true} and
		.mouse == true and
		.attention == {
			"enabled": true,
			"notifications": true,
			"sound": false
		} and
		(has("plugin") | not)
	' >/dev/null \
    || scenario_fail 'OpenCode TUI theme or interaction defaults are incorrect'
}

test_regular_profile_trusts_project_configuration() {
  local ocx_config opencode_config

  ocx_config=$REPOSITORY_ROOT/opencode/profiles/regular/ocx.jsonc
  opencode_config=$REPOSITORY_ROOT/opencode/profiles/regular/opencode.jsonc

  jsonc_to_json "$ocx_config" | jq -e \
    '.exclude == ["**/CLAUDE.md"]' >/dev/null \
    || scenario_fail 'regular profile excludes more than CLAUDE.md'

  jsonc_to_json "$opencode_config" | jq -e '
		.permission["linear_*"] == "allow" and
		.mcp.linear == {
			"type": "remote",
			"url": "https://mcp.linear.app/mcp",
			"enabled": false
		}
	' >/dev/null \
    || scenario_fail 'regular profile Linear MCP policy is incorrect'

  jsonc_to_json "$opencode_config" | jq -e '
		.agent.researcher.permission.bash == {
			"glab repo view*": "allow",
			"glab mr view*": "allow",
			"glab mr list*": "allow",
			"glab issue view*": "allow",
			"glab issue list*": "allow",
			"glab release view*": "allow",
			"glab release list*": "allow",
			"glab ci get*": "allow",
			"glab ci list*": "allow",
			"glab ci status*": "allow",
			"glab ci trace*": "allow",
			"glab ci config view*": "allow",
			"glab search *": "allow",
			"glab api *": "allow"
		}
	' >/dev/null \
    || scenario_fail 'regular profile glab permissions are incorrect'
}

test_specialized_profiles_clone_regular_contract_and_route_models() {
  local boost_config go_config profile regular_config regular_dir

  regular_dir=$REPOSITORY_ROOT/opencode/profiles/regular
  regular_config=$regular_dir/opencode.jsonc
  go_config=$REPOSITORY_ROOT/opencode/profiles/go/opencode.jsonc
  boost_config=$REPOSITORY_ROOT/opencode/profiles/boost/opencode.jsonc

  for profile in go boost; do
    cmp -s "$regular_dir/AGENTS.md" \
      "$REPOSITORY_ROOT/opencode/profiles/$profile/AGENTS.md" \
      || scenario_fail "$profile profile instructions diverge from regular"
    cmp -s "$regular_dir/ocx.jsonc" \
      "$REPOSITORY_ROOT/opencode/profiles/$profile/ocx.jsonc" \
      || scenario_fail "$profile OCX policy diverges from regular"
    jq -s -e '
		.[0].permission == .[1].permission and
		.[0].mcp == .[1].mcp and
		.[0].agent.researcher.permission == .[1].agent.researcher.permission
	' <(jsonc_to_json "$regular_config") \
      <(jsonc_to_json \
        "$REPOSITORY_ROOT/opencode/profiles/$profile/opencode.jsonc") >/dev/null \
      || scenario_fail "$profile OpenCode policy diverges from regular"
  done

  jsonc_to_json "$go_config" | jq -e '
		[
			.model,
			.small_model,
			(.agent | to_entries[] | .value.model)
		] | all(startswith("opencode-go/"))
	' >/dev/null \
    || scenario_fail 'go profile uses a model outside OpenCode Go'

  jsonc_to_json "$go_config" | jq -e '
		.model == "opencode-go/grok-4.6" and
		.small_model == "opencode-go/gpt-5.6-luna" and
		.agent.plan == {
			"model": "opencode-go/grok-4.6",
			"variant": "xhigh",
			"temperature": 0.3
		} and
		.agent.build == {
			"model": "opencode-go/glm-5.3",
			"variant": "max",
			"temperature": 0.3
		} and
		.agent.coder == {
			"model": "opencode-go/kimi-k3",
			"variant": "max"
		} and
		.agent.explore == {
			"model": "opencode-go/gpt-5.6-luna",
			"variant": "max"
		} and
		.agent.researcher.model == "opencode-go/qwen3.8-max" and
		(.agent.researcher | has("variant") | not) and
		.agent.scribe.model == "opencode-go/minimax-m3" and
		.agent.scribe.variant == "thinking" and
		.agent.reviewer.model == "opencode-go/deepseek-v4-pro" and
		.agent.reviewer.variant == "max" and
		([.agent[] | (has("reasoningEffort") or has("textVerbosity"))] | any | not)
	' >/dev/null \
    || scenario_fail 'go profile model routing is incorrect'

  jsonc_to_json "$boost_config" | jq -e '
		.model == "openai/gpt-5.6-sol" and
		.small_model == "kimi-for-coding/k3" and
		.agent.plan == {
			"model": "anthropic/claude-opus-5",
			"variant": "max"
		} and
		.agent.build == {
			"model": "openai/gpt-5.6-sol",
			"variant": "max"
		} and
		.agent.coder == {
			"model": "openai/gpt-5.6-luna",
			"variant": "xhigh"
		} and
		.agent.explore == {
			"model": "kimi-for-coding/k3",
			"variant": "max"
		} and
		.agent.researcher.model == "opencode-go/grok-4.6" and
		.agent.researcher.variant == "xhigh" and
		.agent.scribe.model == "minimax-coding-plan/MiniMax-M3" and
		(.agent.scribe | has("variant") | not) and
		.agent.reviewer.model == "zai-coding-plan/glm-5.3" and
		.agent.reviewer.variant == "max" and
		([.agent[] | (has("reasoningEffort") or has("textVerbosity"))] | any | not)
	' >/dev/null \
    || scenario_fail 'boost profile model routing is incorrect'
}

test_installer_links_only_dotfiles_owned_entries() {
  local config_dir fake_bin home profile

  home=$(scenario_tmpdir install)
  fake_bin=$(make_fake_clis "$home")
  config_dir=$home/.config/opencode

  scenario_capture "$home" env HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  for profile in agents commands skills tools ocx.jsonc opencode.jsonc opencode-mem.jsonc tui.jsonc; do
    assert_link_target "$REPOSITORY_ROOT/opencode/$profile" \
      "$config_dir/$profile" "OpenCode $profile"
  done

  for profile in boost regular go; do
    assert_link_target "$REPOSITORY_ROOT/opencode/profiles/$profile" \
      "$config_dir/profiles/$profile" "OpenCode $profile profile"
  done

  assert_contains "$home/events.log" 'ocx profile add regular --global'
  assert_contains "$home/events.log" \
    'ocx profile add go --clone regular --global'
  assert_contains "$home/events.log" \
    'ocx profile add boost --clone regular --global'
  assert_before "$home/events.log" 'ocx profile add regular --global' \
    'ocx profile add go --clone regular --global'

  for profile in plugins .ocx package.json .gitignore profiles/default; do
    [[ -e $config_dir/$profile ]] \
      || scenario_fail "OCX runtime entry was removed: $profile"
    [[ ! -L $config_dir/$profile ]] \
      || scenario_fail "OCX runtime entry was linked: $profile"
  done

  assert_contains "$config_dir/plugins/workspace.ts" 'runtime plugin'
  assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace@'
  assert_contains "$home/events.log" 'ocx add kdco/workspace --global'

  scenario_capture "$home" env HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/opencode/install.sh"

  for profile in agents commands skills tools ocx.jsonc opencode.jsonc opencode-mem.jsonc tui.jsonc; do
    assert_link_target "$REPOSITORY_ROOT/opencode/$profile" \
      "$config_dir/$profile" "OpenCode $profile after reinstall"
  done

  for profile in boost regular go; do
    assert_link_target "$REPOSITORY_ROOT/opencode/profiles/$profile" \
      "$config_dir/profiles/$profile" "OpenCode $profile profile after reinstall"
  done

  assert_contains "$config_dir/plugins/workspace.ts" 'runtime plugin'
  assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace@'
  assert_not_contains "$home/events.log" 'ocx add kdco/workspace'
}

scenario_run 'OpenCode shell defaults to the regular OCX profile' \
  test_shell_uses_regular_ocx_profile_and_shortcuts
scenario_run 'OpenCode versions only the intended editable payload' \
  test_managed_payload_is_complete_and_runtime_payload_is_excluded
scenario_run 'OpenCode TUI matches terminal theme and interaction defaults' \
  test_tui_matches_terminal_theme_and_interaction_defaults
scenario_run 'OpenCode regular profile trusts project configuration' \
  test_regular_profile_trusts_project_configuration
scenario_run 'OpenCode specialized profiles clone regular and route models' \
  test_specialized_profiles_clone_regular_contract_and_route_models
scenario_run 'OpenCode installer links managed entries and preserves OCX runtime state' \
  test_installer_links_only_dotfiles_owned_entries
scenario_finish
