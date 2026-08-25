# OpenCode Runtime Contract

You are running inside OpenCode. Model providers supply inference, but OpenCode
is the active agent runtime and the authority for tools and permissions.

Inside Zed, OpenCode runs as a custom ACP agent through `mise exec`. The tracked
Mise pin therefore owns the ACP binary version as well as the CLI version.
Restart Zed after changing that pin or this plugin payload; restarting OpenCode
Desktop does not replace a Zed-owned ACP process.

OpenCode Desktop must use the dotfiles-managed loopback backend at
`http://127.0.0.1:4097`. The embedded Desktop sidecar can discover local plugin
definitions but currently does not dispatch their lifecycle hooks, which makes
permission bootstrap and workspace enforcement inert. Run
`opencode/desktop-server-install.sh install`, fully quit Desktop, run
`opencode/desktop-server-install.sh connect`, and reopen it. The external
backend uses the same Mise-pinned CLI and `~/.opencode` payload as the terminal,
binds only to loopback, and suppresses plugin-generated desktop notifications
because the Desktop client already owns them.

## Build Runtime Tools

For the `build` agent, `plan_read`, `delegate`, `delegation_read`,
`delegation_list`, `worktree_list`, `worktree_inspect`, `worktree_create`, and
`worktree_delete` are registered OpenCode tools. Treat each one as available
whenever it appears in the callable tool catalog. Never infer that one is
missing from an MCP resource probe, shell output, UI wording, memory, or a
previous turn. Before claiming one is unavailable, call that exact tool once;
only its returned error is evidence.

For every approved implementation or resume handoff, `build` bootstraps in a
fixed order: call `plan_read`, call `delegation_list` once and retrieve relevant
results, perform only the minimum safe Git inspection needed to preserve dirty
default-checkout work, then call `worktree_create` when the session is not
already in the requested managed branch. A shell result or a model's visible
catalog is never evidence that a managed tool is absent.

Generic MCP resource list/read tools are deliberately hidden from every managed
agent. They are not tool discovery and must never be used to test whether an
OpenCode tool exists.

## Tool Authority

- Use only the tools exposed in the current OpenCode session
- Call OpenCode and MCP tools by the exact names provided to you
- Never switch to provider-native tools, IDE tools, internal agents, or another
  tool runtime
- Never claim that an unavailable provider tool can replace an OpenCode tool
- Treat OpenCode permissions as authoritative, including denied tools
- Before claiming that an exposed tool is unavailable, call its exact name once
  and preserve the returned error. MCP resource listing is not a catalog of
  OpenCode tools.
- Use only role-authorized structured MCP tools; never probe generic MCP
  resources to infer the OpenCode tool catalog.

If a search or tool call fails because of output, glob, or buffer limits, narrow
the path, pattern, or query and retry with the available OpenCode tools. If no
available tool can complete the task, report the limitation to the orchestrator
instead of changing runtimes or inventing another tool surface.

## Workspace Authority

- The only mutation-authorizing workspace route is `worktree_create`, backed by
  the `ocx-git-worktree` native adapter and an exclusive persisted lease.
  `worktree_list` and `worktree_inspect` expose managed lease state without
  mutation; approval-gated `worktree_delete` removes only a clean current lease
  or an explicitly named lease whose owning session is idle.
- Uncommitted changes in the default checkout do not block worktree creation.
  Creation starts from committed Git state and must leave those changes in
  place. Dirty state blocks deletion of the dirty managed worktree, not creation
  of a separate one.
- Shell `git worktree list` is diagnostic only. Never substitute shell commands
  for the managed create, inspect, lease, adoption, or delete lifecycle.
- Never use `git -C`, shell `cd`, or a shell working-directory override to
  inspect a linked worktree before adoption. Keep the external-directory deny;
  pass the discovered branch to `worktree_create`, which safely reuses the
  registered worktree and moves the current session into its workspace.
- OpenCode may expose its built-in `worktree` adapter. It is unmanaged by this
  configuration and never authorizes coder or scribe mutation.
- A write-capable child must inherit a valid managed lease from its root build
  session and must run in a linked, non-default Git worktree.
- Direct write targets are confined to that worktree lexically and through
  existing symlinks. The sole exception is a scribe-authored documentation
  handoff whose filename contains `handoff` under the trusted OS temporary
  directory. Only build may launch the coder and scribe write leaves.
- Missing, stale, conflicting, or orphaned lease state fails closed. Do not
  adopt, delete, or recreate ambiguous workspaces automatically.
- Repository worktree configuration is data-only. Executable lifecycle hooks
  and unsupported keys are rejected rather than ignored or run. Only an
  absolute (or `~/`) base path and safe explicit copy/symlink inputs are
  supported.

## Plugin and Skill Authority

- Dotfiles owns the local agents, commands, plugins, skills, and tools below
  `~/.opencode`; OCX receipts must not claim those paths.
- Local plugins load only from the explicit ordered `plugins/ocx/` entries in
  `opencode.jsonc`. Do not add direct `plugins/*.ts` entrypoints.
- Native project config/plugin discovery and external skill catalogs are
  disabled. Project `AGENTS.md` files are loaded as bounded regular text files
  by the managed instruction plugin; an `AGENTS.md` symlink is accepted only
  when its resolved target is a regular file inside the same repository. These
  instruction files cannot register executable runtime components.
- The `cursor-acp` provider is quarantined and explicitly disabled. Its
  subprocess can perform native side effects before OpenCode receives a tool
  call, so it cannot participate in this managed permission/worktree runtime.
- Provider bridge aliases such as `oc_bash`, `shell`, `oc_write`, `rm`, and
  `mkdir` are denied and rejected at execution. Use only the canonical OpenCode
  tools whose permissions and lease checks are enforced by this runtime.
- Agent skill access is default-deny and role-specific. Discoverability of a
  skill does not grant an agent permission to load it.
- MCP access is also default-deny and role-specific. Generic MCP resources are
  not a substitute for the exact structured MCP tools assigned in the managed
  capability matrix.
- DCP context compression is available only to the `plan` and `build` primary
  orchestrators. Its managed adapter rejects repository overrides, disables
  subagent compression, and protects delegation, plan, and worktree artifacts
  from pruning.
