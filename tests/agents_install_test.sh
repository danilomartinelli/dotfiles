#!/usr/bin/env bash
#
# The coding-agent topics: the shared instructions every agent reads, and the
# credential-free settings each agent topic links.

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
scenario_init dotfiles-agents-install-tests

invoke_topic() {
  local fixture=$1
  local topic=$2
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/$topic/install.sh"
}

assert_links_to() {
  local link=$1
  local source=$2

  [ -L "$link" ] || {
    scenario_fail "$link is not a symbolic link"
    return 1
  }
  assert_equal "$source" "$(readlink "$link")" "source of $link"
}

test_every_agent_reads_the_shared_instructions() {
  local fixture instructions
  fixture=$(installer_fixture)
  instructions=$REPOSITORY_ROOT/agents/instructions.md
  invoke_topic "$fixture" agents

  assert_links_to "$fixture/home/.claude/CLAUDE.md" "$instructions"
  assert_links_to "$fixture/home/.codex/AGENTS.md" "$instructions"
  assert_links_to "$fixture/home/.config/opencode/AGENTS.md" "$instructions"
  assert_links_to "$fixture/home/.gemini/AGENTS.md" "$instructions"
}

test_existing_instructions_are_backed_up_once() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/home/.codex"
  printf 'hand-written\n' >"$fixture/home/.codex/AGENTS.md"
  invoke_topic "$fixture" agents

  assert_contains "$fixture/home/.codex/AGENTS.md.backup" 'hand-written'
  assert_links_to "$fixture/home/.codex/AGENTS.md" \
    "$REPOSITORY_ROOT/agents/instructions.md"
}

test_a_second_run_reports_every_link_current() {
  local fixture
  fixture=$(installer_fixture)
  invoke_topic "$fixture" agents
  invoke_topic "$fixture" agents

  assert_count "$fixture/stdout.log" 'instructions already linked' 4
}

test_each_agent_topic_links_its_settings() {
  local fixture
  fixture=$(installer_fixture)
  invoke_topic "$fixture" claude
  cat >"$fixture/fake-bin/mise" <<'EOF'
#!/bin/sh
set -e
[ "$1 $2 $3 $4 $5 $7 $8" = "exec go -- go -C build -o" ]
printf '#!/bin/sh\n' >"$9"
chmod +x "$9"
EOF
  chmod +x "$fixture/fake-bin/mise"
  invoke_topic "$fixture" herdr
  invoke_topic "$fixture" opencode

  assert_links_to "$fixture/home/.claude/settings.json" \
    "$REPOSITORY_ROOT/claude/settings.json"
  assert_links_to "$fixture/home/.claude/impeccable-hook.sh" \
    "$REPOSITORY_ROOT/claude/impeccable-hook.sh"
  assert_links_to "$fixture/home/.config/herdr-app/settings.json" \
    "$REPOSITORY_ROOT/herdr/settings.json"
  assert_links_to "$fixture/home/.config/herdr-app/programs.json" \
    "$REPOSITORY_ROOT/herdr/programs.json"
  assert_links_to "$fixture/home/.config/herdr-app/subagent-hook" "$REPOSITORY_ROOT/herdr/subagent-hook"
  assert_links_to "$fixture/home/.codex/hooks.json" "$REPOSITORY_ROOT/herdr/codex-hooks.json"
  assert_links_to "$fixture/home/.config/herdr-app/themes/catppuccin-macchiato.json" \
    "$REPOSITORY_ROOT/herdr/themes/catppuccin-macchiato.json"
  assert_links_to "$fixture/home/.config/herdr-app/layouts/estro.json" \
    "$REPOSITORY_ROOT/herdr/layouts/estro.json"
  local app_dir="$fixture/home/.config/herdr-app"
  [ -f "$app_dir/mods/better-search/main.js" ] || scenario_fail 'Estro search was not installed'
  cmp "$REPOSITORY_ROOT/herdr/skillshare/mods/skillshare/main.js" "$app_dir/mods/skillshare/main.js" \
    || scenario_fail 'Skillshare was not installed'
  jq -e '
    ([.. | objects | select(.id? == "tabs-row") | .children[] | select(.content.props.role? == "toggle") | .content.mod] == ["skillshare"])
    and ([.. | objects | select(.id? == "work-body") | .children[] | select(.id == "skillshare-panel") | .children[].content.mod] == ["skillshare"])
  ' "$app_dir/layouts/estro.json" >/dev/null || scenario_fail 'Estro must expose the Skillshare toggle and panel'
  for skill in code-review diagnosing-bugs; do
    [ -s "$app_dir/mods/review-findings/skills/$skill/SKILL.md" ] || scenario_fail "Missing Herdr skill: $skill"
  done
  [ -x "$app_dir/mods/branch-pr/bin/herdr-pr" ] || scenario_fail 'Estro PR helper was not built'
  [ -x "$app_dir/mods/branch-issue/bin/herdr-linear" ] || scenario_fail 'Estro issue helper was not built'
  printf 'personal settings\n' >"$app_dir/mods/better-search/mod.json"
  printf 'installed update\n' >"$app_dir/mods/skillshare/version.js"
  ln -s "$(command -v jq)" "$fixture/fake-bin/jq"
  printf '%s\n' '{"global":{"cmd-shift-b":"app.palette"}}' >"$app_dir/keys.json"
  invoke_topic "$fixture" herdr
  jq -e '
    .global["cmd-shift-b"] == "app.palette"
    and .["layout:estro"]["cmd-shift-b"] == null
    and .["layout:estro"]["cmd-alt-p"] == "mod.open:better-search"
  ' "$app_dir/keys.json" >/dev/null || scenario_fail 'Estro shortcut merge did not preserve existing bindings'
  assert_equal 'personal settings' "$(cat "$app_dir/mods/better-search/mod.json")" 'existing mod configuration'
  assert_equal 'installed update' "$(cat "$app_dir/mods/skillshare/version.js")" 'existing Skillshare version'
  assert_links_to "$fixture/home/.config/opencode/opencode.jsonc" \
    "$REPOSITORY_ROOT/opencode/opencode.jsonc"
  assert_links_to "$fixture/home/.config/opencode/tui.jsonc" \
    "$REPOSITORY_ROOT/opencode/tui.jsonc"
}

# Kimi Code read the shared instructions from ~/.agents until it was removed.
test_the_retired_kimi_instructions_link_is_removed() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/home/.agents"
  ln -s "$REPOSITORY_ROOT/agents/instructions.md" "$fixture/home/.agents/AGENTS.md"
  invoke_topic "$fixture" agents

  [ ! -L "$fixture/home/.agents/AGENTS.md" ] \
    || scenario_fail 'the retired Kimi Code link is still present'
}

test_foreign_instructions_at_the_retired_path_are_kept() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/home/.agents"
  printf 'hand-written\n' >"$fixture/home/.agents/AGENTS.md"
  invoke_topic "$fixture" agents

  assert_contains "$fixture/home/.agents/AGENTS.md" 'hand-written'
}

# Mise installs Claude Code with npm, so Claude Code records an npm global
# install and its own updater runs `npm install -g` with whichever Node is
# first on PATH: a copy outside the Mise declaration that shadows it.
# DISABLE_UPDATES also refuses `claude update` and `claude install`.
test_claude_code_leaves_its_version_to_mise() {
  jq -e '.env.DISABLE_UPDATES == "1"' "$REPOSITORY_ROOT/claude/settings.json" >/dev/null \
    || scenario_fail 'claude/settings.json must set env.DISABLE_UPDATES to "1"'
}

# The hooks name the gate through $HOME: a checkout path or a user name in the
# tracked file would point nowhere on another machine.
test_claude_code_hooks_reach_impeccable_only_through_the_gate() {
  jq -e '[.hooks | (.SessionStart, .PostToolUse, .Stop)[] | .hooks[].command
    | select(contains("impeccable"))] | length == 3
    and all(. == "[ ! -x \"$HOME/.claude/impeccable-hook.sh\" ] || \"$HOME/.claude/impeccable-hook.sh\"")' \
    "$REPOSITORY_ROOT/claude/settings.json" >/dev/null \
    || scenario_fail 'every Claude Code hook must run the linked Impeccable gate'
}

# Usage: run_impeccable_gate <fixture> <project>
run_impeccable_gate() {
  local fixture=$1
  local project=$2
  local impeccable=$fixture/home/.claude/skills/impeccable/scripts/impeccable

  mkdir -p "$project"
  scenario_write_executable "$impeccable" <<'EOF'
#!/bin/sh
printf 'ran %s: ' "$1"
cat
EOF
  printf 'hook input' | fixture_run "$fixture" CLAUDE_PROJECT_DIR="$project" \
    -- "$REPOSITORY_ROOT/claude/impeccable-hook.sh"
}

test_the_impeccable_gate_stays_silent_without_a_design_file() {
  local fixture
  fixture=$(installer_fixture)
  run_impeccable_gate "$fixture" "$fixture/project"

  assert_empty "$fixture/stdout.log"
}

test_the_impeccable_gate_passes_the_hook_input_to_an_opted_in_project() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/project"
  : >"$fixture/project/DESIGN.md"
  run_impeccable_gate "$fixture" "$fixture/project"

  assert_contains "$fixture/stdout.log" 'ran hook: hook input'
}

test_the_impeccable_gate_tolerates_a_missing_impeccable() {
  local fixture
  fixture=$(installer_fixture)
  mkdir -p "$fixture/project"
  : >"$fixture/project/DESIGN.md"
  fixture_run "$fixture" CLAUDE_PROJECT_DIR="$fixture/project" \
    -- "$REPOSITORY_ROOT/claude/impeccable-hook.sh" </dev/null
}

# Homebrew installs Grok Build, and Grok's own updater would put a second copy
# below ~/.grok that the cask never sees.
test_grok_build_leaves_its_version_to_homebrew() {
  assert_contains "$REPOSITORY_ROOT/grok/env.zsh" 'export GROK_DISABLE_AUTOUPDATER=1'
}

# Herdr's default Cursor command is `agent`, the name Grok Build also installs.
test_herdr_starts_cursor_by_its_own_name_and_reports_nothing() {
  jq -e '.programs.cursor.run == ["cursor-agent"]' \
    "$REPOSITORY_ROOT/herdr/programs.json" >/dev/null \
    || scenario_fail 'herdr/programs.json must start Cursor as cursor-agent'
  jq -e '.telemetry == false' "$REPOSITORY_ROOT/herdr/settings.json" >/dev/null \
    || scenario_fail 'herdr/settings.json must set telemetry to false'
}

# A `run` override replaces Herdr's own command, so Codex has to carry the
# `--no-daemon` Herdr starts it with: a shared daemon ties later sessions to
# the first terminal.
test_herdr_starts_claude_code_and_codex_without_approval_prompts() {
  jq -e '.programs.claude.run == ["claude", "--dangerously-skip-permissions"]' \
    "$REPOSITORY_ROOT/herdr/programs.json" >/dev/null \
    || scenario_fail 'herdr/programs.json must start Claude Code without permission prompts'
  jq -e '.programs.codex.run
    == ["codex", "--no-daemon", "--dangerously-bypass-approvals-and-sandbox"]' \
    "$REPOSITORY_ROOT/herdr/programs.json" >/dev/null \
    || scenario_fail 'herdr/programs.json must start Codex daemonless and without approvals'
}

test_estro_reads_issues_from_github() {
  jq -e '.settings.provider == "github"' \
    "$REPOSITORY_ROOT/herdr/estro/mods/branch-issue/mod.json" >/dev/null \
    || scenario_fail 'Branch Issue must default to GitHub Issues'
}

scenario_run 'every agent reads the shared instructions' \
  test_every_agent_reads_the_shared_instructions
scenario_run 'existing instructions are backed up once' \
  test_existing_instructions_are_backed_up_once
scenario_run 'a second run reports every link current' \
  test_a_second_run_reports_every_link_current
scenario_run 'each agent topic links its settings' \
  test_each_agent_topic_links_its_settings
scenario_run 'the retired Kimi Code instructions link is removed' \
  test_the_retired_kimi_instructions_link_is_removed
scenario_run 'foreign instructions at the retired path are kept' \
  test_foreign_instructions_at_the_retired_path_are_kept
scenario_run 'Claude Code leaves its version to Mise' \
  test_claude_code_leaves_its_version_to_mise
scenario_run 'Claude Code hooks reach Impeccable only through the gate' \
  test_claude_code_hooks_reach_impeccable_only_through_the_gate
scenario_run 'the Impeccable gate stays silent without a design file' \
  test_the_impeccable_gate_stays_silent_without_a_design_file
scenario_run 'the Impeccable gate passes the hook input to an opted-in project' \
  test_the_impeccable_gate_passes_the_hook_input_to_an_opted_in_project
scenario_run 'the Impeccable gate tolerates a missing Impeccable' \
  test_the_impeccable_gate_tolerates_a_missing_impeccable
scenario_run 'Grok Build leaves its version to Homebrew' \
  test_grok_build_leaves_its_version_to_homebrew
scenario_run 'Herdr starts Cursor by its own name and reports nothing' \
  test_herdr_starts_cursor_by_its_own_name_and_reports_nothing
scenario_run 'Herdr starts Claude Code and Codex without approval prompts' \
  test_herdr_starts_claude_code_and_codex_without_approval_prompts
scenario_run 'Estro reads issues from GitHub' \
  test_estro_reads_issues_from_github

scenario_finish
