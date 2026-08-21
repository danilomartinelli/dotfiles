# Managed OpenCode Capability Matrix

This file is the canonical route map for agents, tools, MCPs, skills, commands,
and managed worktrees. The effective capability is the intersection of tool
registration, global permission, the agent override, and (for mutation) a valid
managed workspace lease. Seeing a name in configuration or discovery does not
authorize its use. When multiple permission rules match, the last match wins.

## Agent Routes

| Agent | Mode | Direct capabilities | Delegation | Skills |
|---|---|---|---|---|
| `plan` | primary, read-only | `question`, `plan_save`, `plan_read`, `compress`, delegation status | `delegate` to read-only `explore`, `researcher`, or `reviewer` | `plan-protocol`, `grilling` |
| `build` | primary orchestrator | local `read`/`glob`/`grep`, allowlisted read-only Git inspection, approved delivery Git operations, managed worktree tools, `plan_read`, `compress` | `delegate` to read-only agents; native `task` only to `coder` and `scribe` from a managed worktree | `code-philosophy`, `frontend-philosophy`, `frontend-design-discipline` |
| `explore` | read-only leaf | `codegraph_codegraph_explore`, local `read`/`glob`/`grep` | none | none |
| `researcher` | read-only leaf | Context7, Exa, grep.app, and `webfetch`; no local filesystem or shell | none | none |
| `coder` | write leaf | CodeGraph, local file mutation, project-local shell verification | none; no worktree or delivery Git lifecycle | `code-philosophy`, `frontend-philosophy`, `frontend-design-discipline`, `deterministic-diagnosis`, `public-seam-tdd` |
| `reviewer` | read-only leaf | local `read`/`glob`/`grep`, plan and delegation evidence | none | `code-review`, `plan-review`, `code-philosophy`, `frontend-philosophy`, `frontend-design-discipline` |
| `scribe` | documentation write leaf | local documentation `read`/`glob`/`grep` plus `apply_patch` for approved prose extensions | none; shell is denied | `writing-for-agents` |

Only `plan` and `build` orchestrate. Read-only leaves use the asynchronous
`delegate` route. Write-capable leaves use native `task`, and only `build` may
launch them after its session owns a managed, non-default worktree.
The ungoverned built-in `general` subagent is disabled. Hidden host agents such
as `compaction`, `summary`, and `title` remain internal lifecycle components,
not user-selectable delegation targets.

## Managed Worktrees and Native Workspaces

- `worktree_list`, `worktree_inspect`, `worktree_create`, and approval-gated
  `worktree_delete` are registered only for `build`.
- Before claiming one of these tools is unavailable, `build` must call its exact
  exposed name once and report the returned error verbatim.
- `list_mcp_resources` and `list_mcp_resource_templates` enumerate MCP
  resources. They do not enumerate OpenCode tools and cannot establish whether
  a worktree tool is available.
- A dirty default checkout is not a creation blocker. `worktree_create` creates
  or adopts an isolated workspace from committed Git state and leaves those
  default-checkout changes untouched.
- Dirty state blocks `worktree_delete`, because managed deletion is intentionally
  fail-closed. Ambiguous, stale, mismatched, or actively leased worktrees are
  reported without automatic pruning, overwrite, or removal.
- `git worktree list` is read-only diagnostic evidence. Shell Git commands never
  replace managed tools for create, adopt, inspect, lease, or delete lifecycle.
- A linked sibling worktree remains an external directory until adoption. Do
  not inspect it with `git -C`, shell `cd`, or a shell cwd override; pass its
  branch to `worktree_create`, which safely reuses the registered worktree and
  resumes the same session inside it.

## Git Inspection and Delivery

`build` owns Git inspection and explicitly authorized final delivery. Safe
inspection includes status, diffs, logs, object/ref inspection, remotes, tags,
stashes, submodule status, `git worktree list`, and exact non-mutating branch
listing variants such as `git branch -a --no-color`.

Staging, commit, fetch, fast-forward-only pull, push, and PR/MR creation remain
approval-gated and require explicit user authorization. Force push is denied.
`coder` may run project verification commands but cannot mutate Git state,
branches, remotes, worktrees, commits, or delivery.

## MCP Routing

The managed global MCP set is deliberately small:

| Server | Exact tools observed in the managed runtime | Authorized agents |
|---|---|---|
| `codegraph` | `codegraph_codegraph_explore` | `explore`, `coder` |
| `context7` | `context7_resolve-library-id`, `context7_query-docs` | `researcher` |
| `exa` | `exa_web_search_exa`, `exa_web_fetch_exa` | `researcher` |
| `gh_grep` | `gh_grep_searchGitHub` | `researcher` |

Local-code agents do not use external-research MCPs. The researcher does not
read the local filesystem. Generic MCP resource listing is denied to agents
whose `read` permission exists for local files; they must use the structured
MCP tools explicitly assigned to their role.

Native project config and plugin discovery is disabled. Consequently,
repository-local MCP declarations are intentionally not merged into this
managed runtime. Add or change an MCP only in the dotfiles-owned global config,
with an explicit role permission and a test for the resolved capability.

## Skill Routing

Skills are discovered from the managed payload, then hidden by default-deny
permissions unless the active role explicitly allows them. A discoverable skill
is not automatically usable. `customize-opencode` and any other built-in or
externally discovered skill remain unapproved unless added to a role above.

Use the smallest relevant skill set. Philosophy skills govern implementation
and review; diagnosis and public-seam TDD load only for their stated defect or
behavior boundaries; `writing-for-agents` is only for agent-facing prose.

## Commands

- `/review` always selects `build`. Build establishes staged, path, or explicit
  merge-base branch evidence and delegates the shell-less analysis to
  `reviewer`.
- `/dcp` opens the managed DCP TUI panel. `/dcp-compress [focus]` requests one
  model-driven compression pass. Compression capability is available only to
  the `plan` and `build` primary orchestrators; protected delegation, plan, and
  worktree artifacts are never pruned by DCP strategies. DCP auto-update is
  disabled because its server and TUI packages are version-pinned here.

Commands are user entrypoints that inject prompts. They do not bypass the
selected agent's effective permissions, workspace lease, or plugin guards.
`/init` and other host-provided entries remain OpenCode built-ins; they are not
dotfiles-owned orchestration commands. Skill discovery entries that the host
shows in its command catalog retain the same per-agent skill permissions above.
