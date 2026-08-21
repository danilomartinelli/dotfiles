# OpenCode Runtime Contract

You are running inside OpenCode. Model providers supply inference, but OpenCode
is the active agent runtime and the authority for tools and permissions.

## Tool Authority

- Use only the tools exposed in the current OpenCode session
- Call OpenCode and MCP tools by the exact names provided to you
- Never switch to provider-native tools, IDE tools, internal agents, or another
  tool runtime
- Never claim that an unavailable provider tool can replace an OpenCode tool
- Treat OpenCode permissions as authoritative, including denied tools

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
  by the managed instruction plugin; they cannot register executable runtime
  components.
- The `cursor-acp` provider is quarantined and explicitly disabled. Its
  subprocess can perform native side effects before OpenCode receives a tool
  call, so it cannot participate in this managed permission/worktree runtime.
- Provider bridge aliases such as `oc_bash`, `shell`, `oc_write`, `rm`, and
  `mkdir` are denied and rejected at execution. Use only the canonical OpenCode
  tools whose permissions and lease checks are enforced by this runtime.
- Agent skill access is default-deny and role-specific. Discoverability of a
  skill does not grant an agent permission to load it.
- DCP context compression is available only to the `plan` and `build` primary
  orchestrators. Its managed adapter rejects repository overrides, disables
  subagent compression, and protects delegation, plan, and worktree artifacts
  from pruning.
