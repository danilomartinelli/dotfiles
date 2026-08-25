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
		[[ -f $REPOSITORY_ROOT/opencode/$managed_path ]] ||
			scenario_fail "managed OpenCode payload is missing: $managed_path"
	done

	while IFS= read -r jsonc_path; do
		jq empty "$jsonc_path" ||
			scenario_fail "OpenCode JSONC is not valid JSON: ${jsonc_path#"$REPOSITORY_ROOT/"}"
	done < <(find "$REPOSITORY_ROOT/opencode" -type f -name '*.jsonc' -print | sort)

	for managed_path in plugins .ocx package.json .gitignore; do
		[[ ! -e $REPOSITORY_ROOT/opencode/$managed_path ]] ||
			scenario_fail "runtime or legacy OpenCode payload is versioned: $managed_path"
	done
}

test_installer_links_only_dotfiles_owned_entries() {
	local config_dir fake_bin home profile

	home=$(scenario_tmpdir install)
	fake_bin=$(make_fake_clis "$home")
	config_dir=$home/.config/opencode

	scenario_capture "$home" env HOME="$home" \
		PATH="$fake_bin:/usr/bin:/bin" \
		"$REPOSITORY_ROOT/opencode/install.sh"

	for profile in agents commands skills tools ocx.jsonc opencode.jsonc; do
		assert_link_target "$REPOSITORY_ROOT/opencode/$profile" \
			"$config_dir/$profile" "OpenCode $profile"
	done

	for profile in boost regular go; do
		assert_link_target "$REPOSITORY_ROOT/opencode/profiles/$profile" \
			"$config_dir/profiles/$profile" "OpenCode $profile profile"
	done

	for profile in plugins .ocx package.json .gitignore profiles/default; do
		[[ -e $config_dir/$profile ]] ||
			scenario_fail "OCX runtime entry was removed: $profile"
		[[ ! -L $config_dir/$profile ]] ||
			scenario_fail "OCX runtime entry was linked: $profile"
	done

	assert_contains "$config_dir/plugins/workspace.ts" 'runtime plugin'
	assert_contains "$config_dir/.ocx/receipt.jsonc" '::kdco/workspace@'
	assert_contains "$home/events.log" 'ocx add kdco/workspace --global'

	scenario_capture "$home" env HOME="$home" \
		PATH="$fake_bin:/usr/bin:/bin" \
		"$REPOSITORY_ROOT/opencode/install.sh"

	for profile in agents commands skills tools ocx.jsonc opencode.jsonc; do
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
scenario_run 'OpenCode installer links managed entries and preserves OCX runtime state' \
	test_installer_links_only_dotfiles_owned_entries
scenario_finish
