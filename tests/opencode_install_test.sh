#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
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
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc" \
    '"{env:OPENCODE_CONFIG_DIR}/tools/runtime.md"'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc" \
    '"{env:OPENCODE_CONFIG_DIR}/tools/capabilities.md"'
  [[ -f $REPOSITORY_ROOT/opencode/opencode.symlink/tools/philosophy.md ]] \
    || scenario_fail 'managed philosophy instructions are missing'
  [[ -f $REPOSITORY_ROOT/opencode/opencode.symlink/tools/runtime.md ]] \
    || scenario_fail 'managed runtime instructions are missing'
  [[ -f $REPOSITORY_ROOT/opencode/opencode.symlink/tools/capabilities.md ]] \
    || scenario_fail 'managed capability matrix is missing'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/runtime.md" \
    'Model providers supply inference, but OpenCode'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/runtime.md" \
    'Never switch to provider-native tools, IDE tools, internal agents, or another'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/runtime.md" \
    'If a search or tool call fails because of output, glob, or buffer limits'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/runtime.md" \
    'instead of changing runtimes or inventing another tool surface.'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/capabilities.md" \
    'A dirty default checkout is not a creation blocker.'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/capabilities.md" \
    '`list_mcp_resources` and `list_mcp_resource_templates` enumerate MCP'
}

test_selective_skill_payloads_are_present_discoverable_and_scoped() {
  local config skills_dir skill skill_name
  local -a approved_skills

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  skills_dir=$REPOSITORY_ROOT/opencode/opencode.symlink/skills
  approved_skills=(
    code-philosophy
    code-review
    deterministic-diagnosis
    frontend-design-discipline
    frontend-philosophy
    grilling
    plan-protocol
    plan-review
    public-seam-tdd
    writing-for-agents
  )

  for skill in "${approved_skills[@]}"; do
    [[ -f $skills_dir/$skill/SKILL.md ]] \
      || scenario_fail "approved skill payload is missing: $skill"
    assert_contains "$skills_dir/$skill/SKILL.md" "name: $skill"
  done

  while IFS= read -r skill_dir; do
    skill_name=$(basename -- "$skill_dir")
    case " ${approved_skills[*]} " in
      *" $skill_name "*) ;;
      *) scenario_fail "unapproved skill payload is present: $skill_name" ;;
    esac
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d -print | sort)

  # The managed payload is discovered from the OpenCode config directory's
  # conventional skills directory; no broad external catalog is configured.
  assert_not_contains "$config" '"skills":'
  [[ ! -e $skills_dir/ask-matt ]] \
    || scenario_fail 'the unapproved full Matt catalog payload is present'
  [[ ! -e $skills_dir/taste ]] \
    || scenario_fail 'the deferred Taste payload is present'
}

test_selective_skill_routes_are_relevant_and_taste_is_not_global() {
  local config coder reviewer scribe review_command code_review_skill

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  coder=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/coder.md
  reviewer=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/reviewer.md
  scribe=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/scribe.md
  review_command=$REPOSITORY_ROOT/opencode/opencode.symlink/commands/review.md
  code_review_skill=$REPOSITORY_ROOT/opencode/opencode.symlink/skills/code-review/SKILL.md

  assert_contains "$config" "load \`grilling\` and ask precise questions"
  assert_contains "$config" "use the local \`deterministic-diagnosis\` skill"
  assert_contains "$config" "use \`public-seam-tdd\`"
  assert_not_contains "$config" 'diagnosing-bugs'
  assert_not_contains "$config" 'ask-matt'
  assert_not_contains "$config" 'taste'

  assert_contains "$coder" "load \`deterministic-diagnosis\`"
  assert_contains "$coder" "load \`public-seam-tdd\`"
  assert_contains "$reviewer" 'fixed-point three-dot diff review'
  assert_contains "$reviewer" 'Standards versus Spec'
  assert_contains "$scribe" "Load \`writing-for-agents\`"
  assert_contains "$review_command" 'fixed-point three-dot diff'
  assert_contains "$review_command" 'Standards and Spec as independent axes'
  assert_contains "$review_command" 'agent: build'
  assert_contains "$code_review_skill" 'fixed-point'
  assert_contains "$code_review_skill" 'Standards axis'
  assert_contains "$code_review_skill" 'Spec axis'

  [[ ! -e $REPOSITORY_ROOT/opencode/opencode.symlink/commands/taste.md ]] \
    || scenario_fail 'Taste is registered as a command without a target'
  [[ ! -e $REPOSITORY_ROOT/opencode/opencode.symlink/commands/taste-audit.md ]] \
    || scenario_fail 'Taste audit is registered without a target'
}

test_unmanaged_runtime_discovery_is_disabled() {
  local home output

  home=$(scenario_tmpdir controlled-discovery)
  # shellcheck disable=SC2016 # Expanded by the nested Zsh, not this Bash test.
  output=$(env HOME="$home" /bin/zsh -c \
    'source "$1"; print -r -- "$OPENCODE_DISABLE_PROJECT_CONFIG|$OPENCODE_DISABLE_EXTERNAL_SKILLS|$OPENCODE_DISABLE_CLAUDE_CODE_SKILLS|${CURSOR_ACP_TOOL_LOOP_MODE-unset}"' \
    zsh "$REPOSITORY_ROOT/opencode/env.zsh") || return 1

  assert_equal 'true|true|true|unset' "$output" \
    'OpenCode controlled discovery without an active Cursor bridge'
}

test_experimental_workspace_runtime_is_enabled() {
  local home output

  home=$(scenario_tmpdir workspace-runtime)
  # shellcheck disable=SC2016 # Expanded by the nested Zsh, not this Bash test.
  output=$(env HOME="$home" /bin/zsh -c \
    'source "$1"; print -r -- "$OPENCODE_EXPERIMENTAL_WORKSPACES"' \
    zsh "$REPOSITORY_ROOT/opencode/env.zsh") || return 1

  assert_equal 'true' "$output" 'native workspace runtime flag'
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
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/package.json" \
    "\"@opencode-ai/sdk\": \"$opencode_version\""
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/.gitignore" \
    'package-lock.json'
  assert_not_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/.gitignore" \
    'bun.lock'
}

test_unsafe_cursor_provider_is_quarantined() {
  local config package

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  package=$REPOSITORY_ROOT/opencode/opencode.symlink/package.json

  if ! bun --cwd "$REPOSITORY_ROOT/opencode/opencode.symlink" -e '
    import { parse } from "jsonc-parser";
    const config = parse(await Bun.file("opencode.jsonc").text());
    if (!config.disabled_providers?.includes("cursor-acp")) process.exit(1);
    if (config.provider?.["cursor-acp"]) process.exit(1);
    if (config.plugin?.some((entry) => String(entry).includes("cursor"))) process.exit(1);
  '; then
    scenario_fail 'cursor-acp entered the active provider or plugin graph'
  fi

  assert_not_contains "$package" '"@rama_nigg/open-cursor"'
  assert_not_contains "$package" '"@ai-sdk/openai-compatible"'
  assert_not_contains "$REPOSITORY_ROOT/mise/config.toml" \
    '"npm:@rama_nigg/open-cursor"'
  [[ ! -e $REPOSITORY_ROOT/opencode/opencode.symlink/plugins/ocx/open-cursor-provider.ts ]] \
    || scenario_fail 'quarantined Cursor provider adapter is still executable'
  # Markdown code spans are intentionally literal assertions.
  # shellcheck disable=SC2016
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/tools/runtime.md" \
    'The `cursor-acp` provider is quarantined and explicitly disabled.'
}

test_dcp_uses_one_pinned_managed_adapter() {
  local adapter config dcp_version package tui

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  package=$REPOSITORY_ROOT/opencode/opencode.symlink/package.json
  tui=$REPOSITORY_ROOT/opencode/opencode.symlink/tui.json
  adapter=$REPOSITORY_ROOT/opencode/opencode.symlink/plugins/ocx/dcp.ts
  dcp_version=3.1.15

  assert_contains "$package" \
    "\"@tarquinen/opencode-dcp\": \"$dcp_version\""
  assert_contains "$package" '"solid-js": "1.9.12"'
  assert_not_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/bun.lock" \
    '@opencode-ai/sdk@1.18.18'
  assert_not_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/bun.lock" \
    'solid-js@1.9.15'
  assert_contains "$config" '"./plugins/ocx/dcp.ts"'
  assert_not_contains "$config" '"@tarquinen/opencode-dcp@'
  assert_contains "$adapter" 'assertNoProjectDcpOverride'
  assert_contains "$tui" "\"@tarquinen/opencode-dcp@$dcp_version\""
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/dcp.jsonc" \
    '"allowSubAgents": false'
  assert_contains "$REPOSITORY_ROOT/opencode/opencode.symlink/dcp.jsonc" \
    '"autoUpdate": false'
}

test_installer_accepts_generated_xdg_runtime_cache() {
  local home fake_bin runtime_dir

  home=$(scenario_tmpdir generated-xdg-cache)
  fake_bin=$(make_fake_clis "$home")
  runtime_dir=$home/.config/opencode
  mkdir -p "$runtime_dir/node_modules" "$runtime_dir/plugin" \
    "$runtime_dir/skills" "$runtime_dir/logs"
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"
  scenario_write_file "$runtime_dir/package.json" <<'EOF'
{
  "dependencies": {
    "@opencode-ai/plugin": "1.18.18"
  }
}
EOF
  scenario_write_file "$runtime_dir/dcp.jsonc" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/Opencode-DCP/opencode-dynamic-context-pruning/master/dcp.schema.json",
}
EOF
  scenario_write_file "$runtime_dir/package-lock.json" <<'EOF'
{}
EOF
  scenario_write_file "$runtime_dir/.gitignore" <<'EOF'
node_modules
EOF

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/stdout.log" \
    "OpenCode config available at $home/.opencode"
}

test_installer_keeps_cursor_provider_quarantined_without_remote_execution() {
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
exit 99
EOF
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_not_contains "$home/events.log" 'curl '
  [[ ! -e $home/.local/bin/cursor-agent ]] \
    || scenario_fail 'installer unexpectedly created Cursor Agent'
  assert_contains "$home/stdout.log" \
    'cursor-acp is quarantined: provider-native effects cannot be gated'
  assert_not_contains "$home/stdout.log" 'Authenticate Cursor Agent'
}

test_agent_delivery_and_provider_permissions_are_explicit() {
  local config explore researcher worktree

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  explore=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/explore.md
  researcher=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/researcher.md
  worktree=$REPOSITORY_ROOT/opencode/opencode.symlink/plugins/ocx/worktree.ts

  assert_contains "$config" '"bash": "deny"'
  assert_contains "$researcher" 'Shell-based GitHub and GitLab clients are intentionally unavailable'
  # Markdown code spans are intentionally literal assertions.
  # shellcheck disable=SC2016
  assert_contains "$researcher" '`context7_resolve-library-id`, then `context7_query-docs`'
  # shellcheck disable=SC2016
  assert_contains "$researcher" '`gh_grep_searchGitHub` for real-world public GitHub usage patterns'
  # shellcheck disable=SC2016
  assert_contains "$researcher" '`exa_web_search_exa` and `exa_web_fetch_exa`'

  assert_contains "$explore" '## Prime Directive: CodeGraph First'
  assert_contains "$explore" '`codegraph_codegraph_explore` MCP tool'
  assert_contains "$explore" 'never to this read-only agent'
  assert_contains "$explore" '**NEVER** use Context7, Exa, grep.app'
  assert_contains "$REPOSITORY_ROOT/git/gitignore.symlink" '.codegraph/'
  assert_contains "$REPOSITORY_ROOT/README.md" \
    'Each linked worktree receives its own'
  assert_contains "$REPOSITORY_ROOT/.localrc.example" \
    'EXA_API_KEY="<CHANGE_ME>"'

  assert_contains "$config" '"git commit*": "ask"'
  assert_contains "$config" '"git pull --ff-only*": "ask"'
  assert_contains "$config" '"git push*": "ask"'
  assert_contains "$config" '"git push*--force*": "deny"'
  assert_contains "$config" '"git push*-f*": "deny"'
  assert_contains "$config" '"worktree_delete": "deny"'
  assert_contains "$config" '"worktree_delete": "ask"'
  assert_contains "$config" '"./plugins/ocx/workspace-plugin.ts"'
  assert_contains "$config" '"./plugins/ocx/worktree.ts"'
  assert_contains "$config" '"./plugins/ocx/background-agents.ts"'
  assert_contains "$config" '"worktree_create": "allow"'
  assert_contains "$config" 'All implementation requires a dedicated non-default branch'
  # shellcheck disable=SC2016 # Backticks are literal prompt content, not shell substitution.
  assert_contains "$config" 'Build is the sole agent responsible for creating and owning the implementation workspace'
  assert_contains "$config" "binds this same build session to the new workspace"
  assert_contains "$config" 'automatically resume this same session in the workspace'
  assert_contains "$config" 'Do not fork the session, open another terminal, or terminate the parent session.'
  assert_not_contains "$config" 'stop this parent session'
  assert_contains "$config" 'explicit approved implementation handoff, not a session-start hook'
  assert_contains "$config" 'coder never commits or pushes'
  assert_contains "$config" 'Commit only when the user explicitly requests a commit.'
  assert_contains "$config" 'Push only when explicitly requested; never force-push.'
  assert_contains "$config" 'The permission layer asks the user before every staging, commit, fetch, pull, push, or PR/MR creation command'
  assert_contains "$config" 'Before claiming that a managed worktree tool is unavailable'
  assert_contains "$config" 'A dirty default checkout does not block `worktree_create`'
  assert_contains "$config" '"git branch -a --no-color": "allow"'
  assert_contains "$config" '"mcp:*": "deny"'
  assert_contains "$config" '"apply_patch": "allow"'
  assert_not_contains "$config" 'delivery policy'

  assert_contains "$worktree" 'The working tree must already be clean.'
  assert_contains "$worktree" 'Cannot delete a worktree with uncommitted changes.'
  assert_not_contains "$worktree" 'postCreate'
  assert_not_contains "$worktree" 'postRemove'
  assert_not_contains "$worktree" 'chore(worktree): session snapshot'
}

test_plan_task_policy_is_structurally_read_only() {
  local config

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  # shellcheck disable=SC2016 # The embedded Bun program receives shell arguments explicitly.
  if ! bun --cwd "$REPOSITORY_ROOT/opencode/opencode.symlink" -e '
    import { readFileSync } from "node:fs"
    import { parse } from "jsonc-parser"

    const config = parse(readFileSync(process.argv[1], "utf8"))
    const task = config?.agent?.plan?.permission?.task
    const expected = {
      "*": "deny",
    }
    const normalize = (value) => Object.fromEntries(
      Object.entries(value ?? {}).sort(([left], [right]) => left.localeCompare(right))
    )
    if (JSON.stringify(normalize(task)) !== JSON.stringify(normalize(expected))) {
      console.error("plan task policy is not the approved read-only route set")
      process.exit(1)
    }
  ' "$config"; then
    scenario_fail 'plan task policy must deny by default and contain only approved read-only routes'
  fi
}

test_opencode_contracts_are_parseable_and_semantically_aligned() {
  local config skills_dir review_command reviewer coder code_review frontend discipline philosophy readme decision_record taste_reference

  config=$REPOSITORY_ROOT/opencode/opencode.symlink/opencode.jsonc
  skills_dir=$REPOSITORY_ROOT/opencode/opencode.symlink/skills
  review_command=$REPOSITORY_ROOT/opencode/opencode.symlink/commands/review.md
  reviewer=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/reviewer.md
  coder=$REPOSITORY_ROOT/opencode/opencode.symlink/agents/coder.md
  code_review=$skills_dir/code-review/SKILL.md
  frontend=$skills_dir/frontend-philosophy/SKILL.md
  discipline=$skills_dir/frontend-design-discipline/SKILL.md
  philosophy=$REPOSITORY_ROOT/opencode/opencode.symlink/tools/philosophy.md
  readme=$REPOSITORY_ROOT/README.md
  decision_record=$REPOSITORY_ROOT/docs/agent-doctrine/DECISION-RECORD.md
  taste_reference=$REPOSITORY_ROOT/skills/frontend-design-discipline/references/taste-skill.md

  # shellcheck disable=SC2016 # The embedded Bun program receives shell arguments explicitly.
  if ! bun --cwd "$REPOSITORY_ROOT/opencode/opencode.symlink" -e '
    import { readdir, readFile } from "node:fs/promises"
    import { parse } from "jsonc-parser"

    const [configPath, skillsPath, reviewCommandPath, reviewerPath, coderPath,
      codeReviewPath, frontendPath, disciplinePath, philosophyPath, readmePath,
      decisionRecordPath, tasteReferencePath] = process.argv.slice(1)
    const read = (path) => readFile(path, "utf8")
    const fail = (message) => {
      console.error(message)
      process.exit(1)
    }
    const configText = await read(configPath)
    const parseErrors = []
    const config = parse(configText, parseErrors, { allowTrailingComma: true })
    if (parseErrors.length > 0) fail("opencode.jsonc has parse errors")

    const requiredMcps = ["codegraph", "context7", "gh_grep", "exa"]
    for (const name of requiredMcps) {
      const server = config.mcp?.[name]
      if (!server || !server.enabled || !server.type) fail(`MCP is not discoverable: ${name}`)
      if (server.type === "local" && !Array.isArray(server.command)) fail(`local MCP command is not an argv array: ${name}`)
      if (server.type === "remote" && typeof server.url !== "string") fail(`remote MCP URL is missing: ${name}`)
    }

    const reviewerPermission = config.agent?.reviewer?.permission ?? {}
    if (reviewerPermission.bash !== "deny") fail("reviewer shell access is not denied")
    const localReadOnly = (permission) => permission?.["*"] === "allow" && permission?.["mcp:*"] === "deny"
    if (!localReadOnly(reviewerPermission.read) || reviewerPermission.glob !== "allow" || reviewerPermission.grep !== "allow") {
      fail("reviewer does not have the structured local inspection tools")
    }
    const reviewerSkills = reviewerPermission.skill ?? {}
    for (const skill of ["code-review", "plan-review", "code-philosophy"]) {
      if (reviewerSkills[skill] !== "allow") fail(`reviewer skill is not allowlisted: ${skill}`)
    }
    if (reviewerSkills["*"] !== "deny") fail("reviewer skills are not default-deny")

    const coderPermission = config.agent?.coder?.permission ?? {}
    const coderSkills = coderPermission.skill ?? {}
    if (coderPermission.write !== "allow" || coderPermission.edit !== "allow" || coderSkills["*"] !== "deny") {
      fail("coder does not have the existing write/edit permissions plus explicit skill access")
    }
    if (coderSkills["code-philosophy"] !== "allow" || coderSkills["public-seam-tdd"] !== "allow") {
      fail("coder implementation skills are not explicitly allowlisted")
    }

    const planPermission = config.agent?.plan?.permission ?? {}
    if (planPermission.delegate !== "allow" || JSON.stringify(planPermission.task) !== JSON.stringify({ "*": "deny" })) {
      fail("plan delegation is not restricted to the read-only async route")
    }
    const buildTask = config.agent?.build?.permission?.task ?? {}
    if (buildTask["*"] !== "deny" || buildTask.coder !== "allow" || buildTask.scribe !== "allow" || Object.keys(buildTask).length !== 3) {
      fail("build native task routes are not limited to write-capable leaves")
    }

    const [reviewCommand, reviewer, coder, codeReview, frontend, discipline, philosophy, readme, decisionRecord, tasteReference] =
      await Promise.all([reviewCommandPath, reviewerPath, coderPath, codeReviewPath, frontendPath, disciplinePath, philosophyPath, readmePath, decisionRecordPath, tasteReferencePath].map(read))
    if (!/recent\s+<base-ref>/.test(reviewCommand) || !reviewCommand.includes("git merge-base") || /git diff HEAD~1|since last commit using/.test(reviewCommand)) fail("review command does not define an explicit merge-base branch mode")
    if (!reviewCommand.includes("git diff --cached") || !reviewCommand.includes("not a three-dot")) fail("review command does not keep staged mode distinct")
    if (!reviewer.includes("explicit base ref, merge-base, and diff") || !reviewer.includes("HEAD~1") || !reviewer.includes("supplied diff")) {
      fail("reviewer does not require the orchestrator-supplied comparison contract")
    }
    if (!codeReview.includes("git merge-base") || !codeReview.includes("HEAD~1") || !codeReview.includes("git diff --cached")) {
      fail("code-review skill lacks the complete comparison contract")
    }
    const section = (source, heading, nextHeading) => {
      const start = source.indexOf(heading)
      if (start < 0) return ""
      const bodyStart = start + heading.length
      const end = source.indexOf(nextHeading, bodyStart)
      return source.slice(bodyStart, end < 0 ? source.length : end)
    }
    const testPolicy = section(coder, "## Responsibilities", "## Tools Available")
    const autonomousAuthority = section(coder, "## Authority: Autonomous Actions", "## Process")
    const forbiddenActions = section(coder, "## FORBIDDEN ACTIONS", "## Bash Command Guidelines")
    if (!/Test changes \(creating, modifying, or fixing tests\) require either one explicit orchestrator assignment that covers the behavior or defect and names `public-seam-tdd` and\/or `deterministic-diagnosis`, or an explicit user\/orchestrator instruction to change tests\./.test(testPolicy)) fail("coder test-change gate is not explicit")
    if (!/Fix tests broken by YOUR changes only when the explicit test-change gate above is satisfied/.test(autonomousAuthority)) fail("coder autonomous test repair is not gated")
    if (/- Fix tests that YOUR changes broke(?! only when)/.test(autonomousAuthority)) fail("coder has contradictory autonomous test authorization")
    const normalizedForbiddenActions = forbiddenActions.replace(/\s+/g, " ").trim()
    if (!normalizedForbiddenActions.includes("NEVER** write tests unless the explicit test-change gate above is satisfied") || !normalizedForbiddenActions.includes("explicit user/orchestrator instruction to change tests")) fail("coder test prohibition contradicts the explicit test-change gate")

    const skillNames = await readdir(skillsPath, { withFileTypes: true })
    const requiredSkills = ["frontend-design-discipline", "frontend-philosophy", "code-review"]
    for (const name of requiredSkills) {
      if (!skillNames.some((entry) => entry.isDirectory() && entry.name === name)) fail(`skill directory is not discoverable: ${name}`)
    }
    for (const entry of skillNames) {
      if (!entry.isDirectory()) continue
      const skillFile = `${skillsPath}/${entry.name}/SKILL.md`
      const source = await read(skillFile).catch(() => "")
      const frontmatter = source.match(/^---\n([\s\S]*?)\n---/)
      if (!frontmatter) fail(`skill frontmatter is missing: ${entry.name}`)
      const declaredName = frontmatter[1].match(/^name:\s*([^\n]+)$/m)?.[1]?.trim()
      const description = frontmatter[1].match(/^description:\s*(.+)$/m)?.[1]?.trim()
      if (declaredName !== entry.name || !description) fail(`skill metadata is not discoverable: ${entry.name}`)
    }
    if (!/^# Frontend Design Discipline/m.test(discipline) || !discipline.includes("## Audit first") || !discipline.includes("## Preflight")) fail("frontend design discipline is missing its audit-first preflight")
    const frontendDisciplineRule = /Load (?:\*\*)?`frontend-design-discipline`(?:\*\*)? only when all three conditions are met: \(1\) the task identifies a frontend\/UI target or surface; \(2\) the work is visual or interactive; and \(3\) the task creates a new surface or substantially redesigns an existing one\./
    const normalizeMarkdown = (source) => source.replace(/\s+/g, " ").trim()
    for (const source of [philosophy, coder, reviewer]) {
      const normalizedSource = normalizeMarkdown(source)
      if (!frontendDisciplineRule.test(normalizedSource)) fail("frontend design discipline routing is not unified")
      if (!normalizedSource.includes("Do not load it for minor adjustments, mechanical maintenance, or frontend work that fails any condition.")) fail("frontend design discipline has no negative routing case")
    }
    const normalizedDiscipline = normalizeMarkdown(discipline)
    if (!normalizedDiscipline.includes("Use this skill only when all three conditions are met") || !normalizedDiscipline.includes("Do not load it for minor adjustments, mechanical maintenance, or frontend work that fails any condition.")) fail("frontend design discipline skill lacks executable eligibility and exclusions")
    const hasConcept = (source, patterns) => patterns.some((pattern) => pattern.test(normalizeMarkdown(source).toLowerCase()))
    const assertCompleteEligibilityPredicate = (source, label) => {
      const normalizedSource = normalizeMarkdown(source).toLowerCase()
      const hasFrontendTarget = [
        /\b(?:frontend|front-end|front end|ui|user interface)\b[\s\S]{0,120}\b(?:target|surface|screen|page|component|interface)\b/,
        /\b(?:target|surface|screen|page|component|interface)\b[\s\S]{0,120}\b(?:frontend|front-end|front end|ui|user interface)\b/,
      ].some((pattern) => pattern.test(normalizedSource))
      const hasVisualOrInteractiveWork = hasConcept(source, [
        /\b(?:visual|visually|interaction|interactive|interactivity)\b/,
      ])
      const hasNewSurfaceOrSubstantialRedesign = hasConcept(source, [
        /\b(?:new|newly|creat(?:e|es|ed|ing|ion)|introduc(?:e|es|ed|ing))\b[\s\S]{0,80}\b(?:surface|screen|page|component|interface|experience)\b/,
        /\b(?:substantial(?:ly)?|major|significant|extensive|large[- ]scale)\b[\s\S]{0,50}\b(?:redesign|rework|revision)(?:s|ed|ing)?\b/,
        /\b(?:redesign|rework|revision)(?:s|ed|ing)?\b[\s\S]{0,50}\b(?:substantial(?:ly)?|major|significant|extensive|large[- ]scale)\b/,
      ])
      if (!hasFrontendTarget || !hasVisualOrInteractiveWork || !hasNewSurfaceOrSubstantialRedesign) {
        const missing = [
          !hasFrontendTarget && "an identifiable frontend/UI target or surface",
          !hasVisualOrInteractiveWork && "visual or interactive work",
          !hasNewSurfaceOrSubstantialRedesign && "a new surface or substantial redesign",
        ].filter(Boolean).join(", ")
        fail(`${label} does not express the complete frontend design eligibility predicate; missing: ${missing}`)
      }
    }
    for (const [label, source] of [
      ["decision record", decisionRecord],
      ["README", readme],
      ["Taste reference", tasteReference],
    ]) assertCompleteEligibilityPredicate(source, label)
    if (/5 Pillars|Typography with Character|Committed Color|gradient meshes|Avoid Inter/.test(frontend)) fail("frontend philosophy still imposes a visual style")
    for (const source of [coder, reviewer, philosophy]) {
      if (/Typography.*Distinctive|Color.*Bold|Motion.*Purposeful|Atmosphere.*gradient/i.test(source)) fail("visual checklist is duplicated outside frontend skills")
    }
    if (!readme.includes("docs/agent-doctrine/DECISION-RECORD.md")) fail("scribe-owned decision-record path is no longer documented")
  ' "$config" "$skills_dir" "$review_command" "$reviewer" "$coder" "$code_review" "$frontend" "$discipline" "$philosophy" "$readme" "$decision_record" "$taste_reference"; then
    scenario_fail 'OpenCode contracts must parse and remain semantically aligned'
  fi
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

  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"

  assert_contains "$home/stdout.log" "OpenCode config available at $home/.opencode"
  assert_contains "$home/stdout.log" 'ocx CLI available'
  assert_contains "$home/stdout.log" 'opencode CLI available'
  assert_equal "$REPOSITORY_ROOT/opencode/opencode.symlink" \
    "$(readlink "$home/.opencode")" 'managed OpenCode link target'
  assert_contains "$receipt" '"untouched": true'
  assert_contains "$receipt" '"./tools/philosophy.md"'
  [[ ! -e $home/.config/opencode ]] \
    || scenario_fail 'installer recreated the legacy XDG config directory'

  receipt_hash=$(shasum -a 256 "$receipt" | cut -d' ' -f1)
  scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"
  assert_equal "$receipt_hash" \
    "$(shasum -a 256 "$receipt" | cut -d' ' -f1)" \
    'OCX receipt after idempotent reinstall'
}

test_installer_rejects_overlapping_ocx_ownership() {
  local home fake_bin status

  home=$(scenario_tmpdir ocx-ownership)
  fake_bin=$(make_fake_clis "$home")
  mkdir -p "$home/.ocx"
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"
  scenario_write_file "$home/.ocx/receipt.jsonc" <<'EOF'
{
  "installed": {
    "component": {
      "files": [{ "path": ".opencode/plugins/ocx/worktree.ts", "hash": "test" }]
    }
  }
}
EOF

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"; then
    scenario_fail 'installer accepted dual OCX and dotfiles ownership'
  else
    status=$?
  fi

  assert_equal 1 "$status" 'overlapping OCX ownership status'
  assert_contains "$home/stderr.log" 'OCX receipt also claims the dotfiles-owned ~/.opencode payload'
}

test_installer_rejects_legacy_xdg_overlay() {
  local home fake_bin status

  home=$(scenario_tmpdir legacy-overlay)
  fake_bin=$(make_fake_clis "$home")
  mkdir -p "$home/.config/opencode"
  ln -s "$REPOSITORY_ROOT/opencode/opencode.symlink" "$home/.opencode"
  scenario_write_file "$home/.config/opencode/opencode.json" <<'EOF'
{ "plugin": ["unmanaged-plugin"] }
EOF

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" "$REPOSITORY_ROOT/opencode/install.sh"; then
    scenario_fail 'installer accepted a shadowing XDG config'
  else
    status=$?
  fi

  assert_equal 1 "$status" 'legacy XDG overlay status'
  assert_contains "$home/stderr.log" 'Legacy OpenCode config can shadow the managed payload'
}

test_installer_explains_missing_bootstrap_link() {
  local home fake_bin status

  home=$(scenario_tmpdir missing)
  fake_bin=$(make_fake_clis "$home")

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
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

  if scenario_capture "$home" env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$home" \
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
scenario_run 'OpenCode keeps selective skill payloads present and scoped' \
  test_selective_skill_payloads_are_present_discoverable_and_scoped
scenario_run 'OpenCode routes skills only to relevant agents' \
  test_selective_skill_routes_are_relevant_and_taste_is_not_global
scenario_run 'OpenCode disables unmanaged runtime discovery' \
  test_unmanaged_runtime_discovery_is_disabled
scenario_run 'OpenCode enables the native workspace runtime' \
  test_experimental_workspace_runtime_is_enabled
scenario_run 'OpenCode plugin dependency follows the pinned CLI version' \
  test_plugin_dependency_matches_pinned_opencode_version
scenario_run 'Unsafe Cursor provider stays quarantined' \
  test_unsafe_cursor_provider_is_quarantined
scenario_run 'DCP has one pinned managed adapter' \
  test_dcp_uses_one_pinned_managed_adapter
scenario_run 'OpenCode installer keeps Cursor quarantined without remote execution' \
  test_installer_keeps_cursor_provider_quarantined_without_remote_execution
scenario_run 'OpenCode agents isolate branches and own explicit delivery' \
  test_agent_delivery_and_provider_permissions_are_explicit
scenario_run 'OpenCode review, TDD, frontend, skill, MCP, and documentation contracts align' \
  test_opencode_contracts_are_parseable_and_semantically_aligned
scenario_run 'OpenCode installer verifies the bootstrap-owned payload' \
  test_installer_verifies_linked_payload_without_relinking
scenario_run 'OpenCode installer rejects overlapping OCX ownership' \
  test_installer_rejects_overlapping_ocx_ownership
scenario_run 'OpenCode installer rejects a legacy XDG overlay' \
  test_installer_rejects_legacy_xdg_overlay
scenario_run 'OpenCode installer accepts generated XDG runtime cache' \
  test_installer_accepts_generated_xdg_runtime_cache
scenario_run 'OpenCode installer explains a missing bootstrap link' \
  test_installer_explains_missing_bootstrap_link
scenario_run 'OpenCode installer normalizes a legacy XDG environment' \
  test_installer_normalizes_legacy_xdg_environment
scenario_run 'OpenCode installer rejects a regular default config directory' \
  test_installer_rejects_default_directory_conflict
scenario_finish
