# OpenCode via OCX

OpenCode and OCX are upstream CLIs installed through Mise. Dotfiles authors the
orchestration plugin and profile sources; it does not fork OCX. OCX assembles
profiles and maintains the worktree and notification components.

## Ownership

The installer links only the entries declared in `opencode/_managed-entries.tsv`
into `~/.config/opencode`. It never replaces the whole configuration directory.

| Owner    | Paths in `~/.config/opencode`                       | Purpose                                                   |
| -------- | --------------------------------------------------- | --------------------------------------------------------- |
| Dotfiles | `orchestrator/`                                     | Workflow, prompts, permissions and pinned memory adapter  |
| Dotfiles | `profiles/regular/`, `profiles/example/`            | Rendered instructions and model routing                   |
| Dotfiles | `ocx.jsonc`, `opencode.jsonc`, `opencode-mem.jsonc` | Registry, common plugins/MCPs and memory storage settings |
| Dotfiles | `tui.jsonc`                                         | Theme, interaction and notification defaults              |
| OCX      | `.ocx/`, `plugins/`, `package.json`, `.gitignore`   | Component receipts, generated code and dependencies       |
| OCX      | `profiles/default/`                                 | Internal initial profile; never selected by the shell     |

Registry payloads are no longer versioned. Do not copy runtime files or receipts
into this repository. Keep retained components byte-intact and validate them with
`ocx verify --cwd "$HOME/.config/opencode" --verbose`.

## Install or refresh

```bash
opencode/install.sh
```

Bootstrap and `dot` also invoke this installer. It installs the orchestrator's
frozen Bun dependencies without lifecycle scripts, initializes OCX, registers
`https://registry.kdco.dev`, and ensures `kdco/worktree` and `kdco/notify` are
installed with their shared `kdco-primitives` dependency.

The installer links the managed entries and refreshes `regular` and `example`.
Custom profiles and payloads remain untouched. Re-running the installer is
supported and leaves session and memory data alone.

The installer refuses activation when workspace/background orchestration hooks
are present. Resolve those components through OCX before installing; the
installer does not migrate or force-remove existing components.

Profile refresh uses `ocx profile remove`, followed by `ocx profile add` and the
managed link. OCX 2.0.15 unlinks a profile symlink without descending into its
source. Recheck this behavior before upgrading OCX; the installer fixtures model
that verified behavior.

Start a new OpenCode process to load changed hooks and prompts. An existing
process keeps its loaded configuration; installation does not restart it.

## Use OpenCode

Open a new Zsh session or run `reload!` after shell changes.

| Command      | Result                                |
| ------------ | ------------------------------------- |
| `opencode`   | Run `ocx opencode` with `OCX_PROFILE` |
| `oc`         | Short form of `opencode`              |
| `oc:regular` | Select `regular` explicitly           |
| `oc:example` | Select `example` explicitly           |

`opencode/env.zsh` declares the default `OCX_PROFILE=regular`. Zed's ACP also
selects `regular`. OpenChamber uses `bin/opencode-profile`, which launches
OpenCode directly with the chosen profile's `OPENCODE_CONFIG` layered over the
global configuration. The adapter supplies the Mise tool environment and
Homebrew paths to OpenCode and its MCP/LSP/shell subprocesses, including when
the desktop app starts without a login-shell `PATH`. It skips automatic
dependency preparation; installation remains part of the normal Mise setup.

The TUI uses Catppuccin Macchiato, `ctrl+x` as leader, `ctrl+p` for commands,
accelerated scrolling, a blinking block cursor and silent notifications.

### Models and roles

<!-- generated: profile-routing -->

| Role       | `regular`                      | `example`                      |
| ---------- | ------------------------------ | ------------------------------ |
| Default    | `openai/gpt-6-astra`           | `openai/gpt-6-astra`           |
| Small      | `openai/gpt-5.6-luna`          | `openai/gpt-5.6-luna`          |
| Plan       | `openai/gpt-6-astra` (`xhigh`) | `openai/gpt-6-astra` (`xhigh`) |
| Build      | `openai/gpt-6-astra` (`xhigh`) | `openai/gpt-6-astra` (`xhigh`) |
| Coder      | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Explore    | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Researcher | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Scribe     | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Reviewer   | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |

<!-- generated-end -->

Supporting agents use `openai/gpt-5.6-luna-fast` with `high`; `small_model` uses
the same standard model. The provider serves that ID from `gpt-5.6-luna` on the
priority tier: same variants, same context limit, only `serviceTier` differs.

`regular` is the active profile; `example` starts with identical routing and
preserves the structure for future customization. Plan/build coordinates the
work. Coder implements and verifies, reviewer checks a supplied focus, scribe
writes documentation, explore investigates code and researcher retrieves
external facts. Supporting roles are used when useful, not as mandatory stages.

A root runs at most three children with explicit focuses and non-overlapping
writer ownership. Corrections resume the same child. Reviews use a source
snapshot and have no fixed round count. Plan saves do not trigger reviews.
Memory is consolidated in the root execution without auxiliary LLM sessions.
Git coders receive a retained, ignored artifact directory inside their checkout
for diagnostics and downloads; see [artifacts and snapshots](orchestrator/README.md#artifacts-and-review-snapshots).
See [runtime behavior and recovery](orchestrator/README.md) and the
[orchestration contract](ORCHESTRATION.md).

### Repository and tracker access

For repository, issue, PR or MR context, the prompts first inspect `git remote -v`
and check `command -v gh` or `command -v glab`. They prefer the matching CLI,
reuse that discovery in delegated work and use `--repo` or API `--hostname` when
needed. Web access is the fallback for missing capabilities or inaccessible
resources, or when explicitly requested by the user.

The read-only runtime guard permits this discovery and supported Git/CLI query
commands, including explicit GET APIs. It rejects mutations, shell composition
and browser-opening flags. Publishing and other writes require existing user
authorization and an appropriate writer delegation.

### Code navigation: LSP and CodeGraph

Both profiles enable native language servers through `lsp: true` in the shared
profile source. `opencode/env.zsh` exports `OPENCODE_EXPERIMENTAL_LSP_TOOL=true`
for both OCX and the direct GUI adapter. The orchestrator permits the native
`lsp` tool for definitions, references, hover, symbols and call hierarchy.
Server availability still depends on the language and its project dependencies;
OpenCode starts applicable servers on demand. See the
[native LSP guide](https://opencode.ai/docs/lsp/).

CodeGraph is already declared through Mise. The common MCP configuration runs
`codegraph serve --mcp`, matching `codegraph install --print-config opencode`.
This declaration replaces running the interactive installer against managed
configuration. Its sole default tool, `codegraph_codegraph_explore`, is allowed
for all seven roles. The MCP and automatic initialization disable CodeGraph
telemetry. CodeGraph answers structural questions across files; LSP supplies
precise language queries. Prompts choose the relevant tool and verify stale or
conflicting results against current source.

On the first session message in a Git checkout, the runtime runs `codegraph init`
only when `.codegraph/` is absent. Nested directories resolve to their checkout
root; linked worktrees get independent indices. Existing directories are
preserved. The initial request waits for initialization, with a three-minute
limit, and concurrent sessions share the work without LLM subsessions. A project
can opt out of both the hook and MCP with `mcp.codegraph.enabled: false`.

The hook respects Git's global ignore. If a ready or newly created index is not
ignored, it appends `/.codegraph/` to the checkout's `.gitignore`, preserving
existing content. Tracked index files and symlinks require explicit repair;
the hook never untracks or deletes them. An interrupted or failed initialization
leaves its directory intact and reports a fallback to file/LSP queries. Inspect
that directory and repair it explicitly with the CodeGraph CLI before starting
a new OpenCode process; retries never launch automatically.

After upgrading CodeGraph, run `codegraph status` in each project. If it reports
an outdated index, run `codegraph index` there to refresh existing data. The
startup hook only creates missing indices; it does not rebuild existing ones.

### Project integrations and skills

Global configuration contains CodeGraph, the common research MCPs and plugins.
Additional integrations belong in the trusted project's OpenCode configuration.
For example, a project can register an optional server and explicitly permit its
tools for coder:

```json
{
  "mcp": {
    "project_tracker": {
      "type": "remote",
      "url": "https://tracker.example.invalid/mcp"
    }
  },
  "agent": {
    "coder": {
      "permission": {
        "project_tracker_*": "allow",
        "project_tracker_delete_item": "deny"
      }
    }
  }
}
```

### Argent device control

`argent` is declared in `mise/config.toml` and its MCP server in
`opencode.jsonc`, with `DO_NOT_TRACK=1` because its telemetry is on by default.
It is enabled, and coder is granted `argent_*` wherever the server is declared,
with `argent_debugger-evaluate` left at `ask` because it evaluates arbitrary
JavaScript inside the running app. The grant lives in `rolePermissions` rather
than in a project's configuration because a profile launch cannot read one, so
a project-side permission would work in the GUI adapter and nowhere else.
Read-only roles get none of it: driving a device is a coder action.

A project that wants a narrower boundary still states it, and coder preserves
it for a configured MCP namespace:

```json
{
  "mcp": { "argent": { "enabled": true } },
  "agent": {
    "coder": {
      "permission": {
        "argent_*": "allow",
        "argent_debugger-evaluate": "ask"
      }
    }
  }
}
```

Device control is a coder action, so nothing is added to the reviewed read-only
query list: build/plan, explore, researcher and reviewer keep their allowlist.

Never run `argent init`. It writes its own editor registration and would leave
an untracked configuration beside the managed one, which `opencode-doctor`
then reports as a shadow. The declaration above replaces it.

Verify the toolchain without OpenCode before blaming the integration, because
every one of these answers comes from the CLI the MCP server wraps:

```bash
argent tools                 # the 76 tools, by name
argent tools describe <name> # arguments of one tool
argent run list-devices      # what the host can actually reach
argent run <tool> --help     # invoke one tool directly, no agent involved
argent server status         # the shared tool-server this MCP talks to
argent telemetry status      # must report disabled through the environment
```

`argent run` is the honest test: a failure there is the device or the SDK, and
a failure only through the MCP is the integration or the permissions above.

### Why the Argent server declares a timeout

`boot-device` on Android is documented as a 2-10 minute operation and Argent
bounds it itself, clamping `bootTimeoutMs` to fifteen minutes. OpenCode's
request timeout defaults to sixty seconds, and a call it abandons does not
abandon the tool-server: the boot runs on, the emulator registers, later calls
briefly reach it, and then the abandoned attempt's own failure path tears the
device down underneath them. What the agent sees is a device that appeared and
then answered `device '<serial>' not found`. The declared `timeout` exists so
the caller outlives the operation it started; a shorter budget belongs in
`bootTimeoutMs`, where Argent can report which stage failed.

### An Android emulator that boots and disappears

Argent hot-boots from the AVD's `default_boot` snapshot when one exists and
falls back to a cold boot when the restore is unusable. It identifies the
emulator it launched by a serial that was not present before, so when the
abandoned hot-boot instance is still draining out of `adb devices`, the cold
boot reusing the same port is never recognized as new. The boot then fails with
`did not register within 60s` and terminates a device that is in fact up; the
message names `-wipe-data`, which is not the smallest repair. Deleting the
snapshot directory is. `~/.android/avd/<avd>.ini` holds the `path=` line that
locates the AVD, and the directory to remove is `<path>/snapshots/default_boot`.
Confirm through `argent run list-devices` that nothing holds the AVD first.
Userdata and the AVD survive; only the hot-boot path is given up, and every
subsequent boot is a cold boot that registers normally.

An emulator that boots through Argent arrives asleep: `dumpsys power` reports
`mWakefulness=Asleep`, and the first-frame probe passes on the all-black screen
that produces. Screenshots are black and the UI tree is a bare `ROOT Screen`
until the device is woken, which reads as a broken emulator and is not one.
Wake it before describing or tapping anything.

Coder preserves explicit permissions for configured MCP namespaces; a server
alone does not grant access. These permissions do not override native tool
boundaries or authorize remote changes. Build/plan, reviewer, explore and
researcher retain their reviewed read-only tool allowlist. Supporting a new MCP
in those roles requires reviewing its query operations in the runtime.

The server named `linear` has reviewed queries for issues, comments, projects,
documents, teams, users, milestones, releases and diff review context. These
are available directly to build/plan, explore, researcher and reviewer, as with
`gh`/`glab` queries; coder and scribe can also retrieve that context. Enable
the server in the project configuration. Creating or changing tracker data
remains a coder operation requiring explicit MCP permission and authorization.
Unknown tools are denied even if the server describes them as read-only.

For other project MCP queries not yet in the reviewed allowlist, build/plan
can delegate to an explicitly permitted coder with a prompt limiting the task
to retrieval. In a Git checkout, use
`ownership: []` when no source/configuration/documentation writes are needed;
coder receives only its automatic artifact directory. There is no need to
grant an unrelated source path or copy tracker content manually. MCP permissions
remain separate from authorization to change tracker data.

Native `list_mcp_resources`, `list_mcp_resource_templates` and
`read_mcp_resource` are available to read-only roles through OpenCode's `read`
permission. They discover and retrieve resources, not the server's callable
tools; an empty resource list does not prove a disconnected server. To check
connection status with the selected profile, run `opencode-profile mcp list`
from the project directory. `enabled: true` connects a server but does not grant
its unapproved tools to a role. The explicit coder permissions shown above
are needed for those operations; build/plan do not inherit them.

A new conversation can reuse the same running directory instance and its
cached configuration. If a fresh CLI sees a configured MCP but the host does
not, compare `/path`, `/config` and `/mcp` on that running server with the
exact worktree directory. Reload an idle directory instance after changing
project configuration; restart OpenCode through its host after changing the
orchestration plugin. Do not infer a credential failure from a different CLI's
status or an agent's missing tools.

Skill discovery for `.agents/skills` is the runtime's own: the home directory
plus every directory from the current one through the Git worktree root, with
explicit `skills.paths` and `skills.urls` preserved. Project `.opencode/skills`
continues to work through normal configuration discovery.

Only `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=true` is set, which keeps both
home-level and project `.claude/skills` out of OpenCode. The broader
`OPENCODE_DISABLE_EXTERNAL_SKILLS` is deliberately unset: despite what
OpenCode's own `customize-opencode` skill claims, that flag guards the whole
discovery block, so it removes a project's `.agents/skills` along with the
home-level scan. Restoring the project paths through `skills.paths` is not
enough either, because a desktop host cannot see that repair. OpenChamber
reads `OPENCODE_DISABLE_EXTERNAL_SKILLS` from its own environment and then
hides every skill whose path contains `.agents/` or `.claude/`, so its slash
menu listed no project skills while the agent could still load all of them.

`ocx opencode -p <profile>` cannot see a project's OpenCode configuration. OCX
collects only `agent`, `command`, `skill` and `tool` directories out of
`.opencode/` into the merged configuration it launches from, so a project's
`opencode.json`, `opencode.jsonc` and `AGENTS.md` never reach the runtime. The
profile's `exclude` and `include` lists filter that collection and cannot add a
file type to it, which is why both stay empty. OCX also strips
`OPENCODE_DISABLE_PROJECT_CONFIG` from the inherited environment and forces it
to `true` whenever a profile is selected, so the shell's own export governs a
bare `opencode` run outside OCX and nothing else.

The direct GUI adapter does not use that launcher. It sets
`OPENCODE_DISABLE_PROJECT_CONFIG=false`, so native discovery loads
`<project>/opencode.json` and `<project>/.opencode/opencode.json`, and a
project's MCP servers, permissions and instructions do apply there. The adapter
also passes `DOTFILES_OPENCODE_PROFILE_CONFIG` so the runtime restores the
selected profile's models after project merging, leaving the declared routes
unchanged. An integration that has to work from the terminal has to be declared
globally instead of by the project.

### Worktrees

`kdco/worktree` exposes `worktree_create` and `worktree_delete`; the installer
provisions it alongside `kdco/notify`. Its per-project configuration is
`.opencode/worktree.jsonc`, and the plugin writes its own empty template into a
checkout that has none, so a repository that needs worktree bootstrapping should
track the file deliberately.

This repository tracks one. A worktree of dotfiles starts without
`opencode/orchestrator/node_modules`, which is untracked and around 686 MB;
until it exists `bun test` cannot resolve `@opencode-ai/plugin` and the
orchestrator suite fails before validating anything. The `postCreate` hook
reinstalls it from the lockfile:

```bash
mise exec -- bun install --frozen-lockfile --ignore-scripts --cwd opencode/orchestrator
```

Reinstalling is deliberate: `sync.symlinkDirs` would share one `node_modules`
across worktrees, so a worktree changing `package.json` or `bun.lock` would
mutate the tree it branched from. Hooks run under `bash -c` without the login
shell, which is why bun is reached through `mise exec`, the adapter
`bin/opencode-profile` already uses. Nothing is copied into a worktree: the only
machine-local file is `.localrc`, and it lives in `$HOME`.

The plugin only logs a failed hook. When orchestrator imports do not resolve in
a worktree, run that command there before investigating further.

Linked worktrees opt out of Git's fsmonitor through
`git/gitconfig.worktree.symlink`, because the daemon segfaults when the worktree
it watches is deleted and leaves the socket behind that makes the next command
fail with `fsmonitor_ipc__send_query`. A process still alive inside a worktree
after its session ends is reported by `opencode-doctor`.

## Edit configuration or profiles

Edit the owning source and use a new process to load the result:

| Concern                                    | Source                                         |
| ------------------------------------------ | ---------------------------------------------- |
| Common plugins and MCPs                    | `opencode/opencode.jsonc`                      |
| Registry                                   | `opencode/ocx.jsonc`                           |
| Memory storage/UI                          | `opencode/opencode-mem.jsonc`                  |
| TUI                                        | `opencode/tui.jsonc`                           |
| Workflow, prompts and permissions          | `opencode/orchestrator/`                       |
| Shared profile instructions and OCX policy | `opencode/profiles/_shared/`                   |
| Optional policy for one profile            | `opencode/profiles/_overrides/<profile>.jsonc` |
| Models and variants                        | `opencode/profiles/_routing.tsv`               |

The profile directories are generated. OCX has no profile inheritance and
`--clone` copies only `ocx.jsonc`; the renderer composes shared policy, optional
overrides and routing into each profile's three payloads:

```bash
_scripts/render-opencode-profiles
_scripts/render-opencode-profiles --check
```

`default` and `small` rows declare `model` and `small_model`. Agent rows use the
roles declared by the profile source. Model settings belong only in routing;
overrides cannot introduce them. A new workflow role also needs a runtime
contract. The renderer rejects unknown, duplicate or incomplete routes.

`variant` is the supported agent reasoning knob. Validate each model and variant
against `bin/opencode-profile models <provider> --verbose` without `--pure`.
Provider options such as `reasoningEffort` are not agent configuration keys.

To add a profile:

1. Add routing rows and a `profile` row to `opencode/_managed-entries.tsv`, with
   `regular` as its clone source.
1. Render the profile and add its `oc:<name>` shortcut to `opencode/aliases.zsh`.
1. Document the profile here, in `README.md` and in `AGENTS.md`.
1. Validate its models, run the focused tests, install and verify its link.

## Update and verify

Update retained registry components with OCX, then check their integrity:

```bash
ocx update --all
opencode/install.sh
ocx verify --cwd "$HOME/.config/opencode" --verbose
```

The local orchestrator and its pinned memory dependency have a separate
[update procedure](orchestrator/README.md#dependencies-and-updates).

```bash
_scripts/test opencode_install
_scripts/test opencode_orchestrator
_scripts/test documentation
```

Fixtures cover generated profiles, model routing, installed ownership,
idempotent installation, conflict rejection, delegation lifecycle, permissions and memory.
Use `_scripts/test` for the complete safe suite after shared/security changes.

For a machine-specific link check:

```bash
find "$HOME/.config/opencode" -maxdepth 2 -type l -print
ocx profile list --global
```

Expected managed links come from `opencode/_managed-entries.tsv`.

## Maintain the runtime state

The configuration above is one half of what OpenCode leaves on a machine. The
other half is its data directory, `~/.local/share/opencode`, and OpenCode
prunes none of it. `opencode-doctor` reports that state and, with `--fix`,
repairs it:

```bash
opencode-doctor
opencode-doctor --fix
opencode-doctor --fix --days 14
opencode-doctor --fix --days 0 --clear-logs
```

`opencode/_doctor.sh` owns the behavior and the command is a thin adapter over
it. `opencode/_runtime-conditions.tsv` declares what it inspects, in the order
it runs, and the table below is rendered from that catalog:

<!-- generated: runtime-conditions -->

| State                      | Doctor                          | Why it accumulates                                                                                        |
| -------------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Worktree processes         | Reported, repaired with `--fix` | A command an agent started outlives the session that started it                                           |
| The `event` table          | Reported, repaired with `--fix` | An append-only replication log for remote workspaces, with no retention                                   |
| Stale `workspace` rows     | Reported, repaired with `--fix` | A row outlives its directory, and a retired adapter fails every server start                              |
| Stranded sessions          | Reported, repaired with `--fix` | A session names a `workspace` row that is gone, so it can be neither deleted nor archived                 |
| Stale session snapshots    | Reported, repaired with `--fix` | A snapshot shadows the directory its `core.worktree` names, and keeps collecting garbage after it goes    |
| Idle delegation artifacts  | Reported, repaired with `--fix` | A delegation's evidence directory outlives the work, and nothing else can tell evidence from build output |
| An untracked global config | Reported only                   | OpenCode reads `opencode.json` as readily as the managed `opencode.jsonc`                                 |
| Log files                  | Reported, repaired with `--fix` | CLI and plugin output, and the rotations it leaves behind                                                 |

<!-- generated-end -->

The event log is the one that grows without bound. Every streaming update of a
message part is stored as a fresh copy of the whole part, so one long session
writes its own transcript back many times over; `message` and `part`, which
hold what a session actually said, stay small beside it. Age alone does not
find the weight: orchestration keeps every session it touches inside any
sensible window. Pruning therefore removes the replication history of every
finished session, one whose newest message is a completed assistant reply,
regardless of age, and of every other session outside the retention window. A
session still owed a reply, or whose reply was cut off, keeps its history for
`--days` days. `--days 0` removes all replication events, including those from
today, and compacts the database. Sessions, messages and memory data remain
intact.

Routine repair rotates the primary log when it exceeds 64 MiB. Add
`--clear-logs` to delete regular `*.log` and numbered rotation files from the
log directory regardless of age or size. Other files, subdirectories and
symlinks are preserved; a symlinked log directory is refused. This option is
read-only without `--fix`.

Reporting is the default because each repair deletes state no backup covers.
Repairs refuse to run while OpenCode holds the database, so quit OpenChamber
and any `opencode` session first. That precondition is also what makes reaping
safe to state: a process still living inside an agent worktree while no
OpenCode runs has no owner left.

A shadowing configuration file is reported and never removed. Adopt what it
declares into `opencode.jsonc`, then delete it by hand.

## Troubleshooting

If `opencode` or `ocx` is missing, reconcile the Mise runtimes:

```bash
mise install
```

If the installer reports a missing source, restore the corresponding path under
`opencode/` before rerunning it. The installer intentionally fails instead of
creating an empty managed configuration.

If an OCX-owned path is missing or damaged, rerun `opencode/install.sh`. Do not
replace `.ocx`, `plugins`, `package.json`, `.gitignore`, or `profiles/default`
with repository links.
