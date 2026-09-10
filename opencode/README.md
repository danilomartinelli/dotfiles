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

The upgrade migration removes the superseded workspace bundle, its old agent,
command and philosophy payloads, and the competing workspace/background hooks
through `ocx remove`. It preserves custom content and stops on modified payloads.
Only components whose receipt paths are all absent may use `--force` to retire
stale metadata; no surviving modified file is force-removed. This handles
checkouts where the retired managed sources have already disappeared.

The installer then links the managed entries and refreshes `regular` and
`example`. Retired `go`/`boost` links are removed only when they point exactly
at this checkout's former sources; local directories and other links survive.
Re-running the installer is supported and leaves session and memory data alone.

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
global configuration.

The TUI uses Catppuccin Macchiato, `ctrl+x` as leader, `ctrl+p` for commands,
accelerated scrolling, a blinking block cursor and silent notifications.

### Models and roles

<!-- generated: profile-routing -->

| Role       | `regular`                      | `example`                      |
| ---------- | ------------------------------ | ------------------------------ |
| Default    | `openai/gpt-5.6-sol`           | `openai/gpt-5.6-sol`           |
| Small      | `openai/gpt-5.6-luna`          | `openai/gpt-5.6-luna`          |
| Plan       | `openai/gpt-5.6-sol` (`xhigh`) | `openai/gpt-5.6-sol` (`xhigh`) |
| Build      | `openai/gpt-5.6-sol` (`xhigh`) | `openai/gpt-5.6-sol` (`xhigh`) |
| Coder      | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Explore    | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Researcher | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Scribe     | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |
| Reviewer   | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) |

<!-- generated-end -->

`regular` is the active profile; `example` starts with identical routing and
preserves the structure for future customization. Plan/build coordinates the
work. Coder implements and verifies, reviewer checks a supplied focus, scribe
writes documentation, explore investigates code and researcher retrieves
external facts. Supporting roles are used when useful, not as mandatory stages.

A root runs at most three children with explicit focuses and non-overlapping
writer ownership. Corrections resume the same child. Reviews use a source
snapshot and have no fixed round count. Plan saves do not trigger reviews.
Memory is consolidated in the root execution without auxiliary LLM sessions.
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

### Project integrations and skills

Global configuration contains the common research MCPs and plugins only.
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

Coder preserves explicit permissions for configured MCP namespaces; a server
alone does not grant access. These permissions do not override native tool
boundaries or authorize remote changes. Build/plan, reviewer, explore and
researcher retain their reviewed read-only tool allowlist. Supporting a new MCP
in those roles requires reviewing its query operations in the runtime.

Automatic discovery of home-level `.agents/skills` and `.claude/skills` is off.
The runtime adds `.agents/skills` from the current directory through the Git
worktree root, including intermediate directories, while preserving explicit
`skills.paths` and `skills.urls`. Outside Git, only the current directory is
automatically added. Project `.opencode/skills`
continues to work through normal configuration discovery. Other tools' global
skill installations are untouched.

OCX profiles have empty `exclude` and `include` lists: OCX merges trusted project
instructions/configuration itself. The shell sets
`OPENCODE_DISABLE_PROJECT_CONFIG=true` to avoid duplicate discovery in that
launch path. The direct GUI adapter overrides it to `false`, because there is
no OCX project merge in that path. The adapter also passes
`DOTFILES_OPENCODE_PROFILE_CONFIG` so the runtime restores the selected profile's
models after project merging. Project integrations remain available without
changing the declared model routes.

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

Fixtures cover generated profiles, model routing, installed ownership, repeated
migration, runtime preservation, delegation lifecycle, permissions and memory.
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
it. It reports and repairs the following state:

| State                      | Why it accumulates                                                           |
| -------------------------- | ---------------------------------------------------------------------------- |
| Log files                  | CLI/plugin output and rotated logs                                           |
| The `event` table          | An append-only replication log for remote workspaces, with no retention      |
| Worktree processes         | A command an agent started outlives the session that started it              |
| Stale `workspace` rows     | A row outlives its directory, and a retired adapter fails every server start |
| An untracked global config | OpenCode reads `opencode.json` as readily as the managed `opencode.jsonc`    |

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
