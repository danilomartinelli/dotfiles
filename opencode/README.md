# OpenCode via OCX

OpenCode and OCX are upstream CLIs installed through Mise. Dotfiles authors the
orchestration plugin and profile sources; it does not fork OCX. OCX assembles
profiles and maintains the worktree and notification components.

## Ownership

The installer links only the entries declared in `opencode/_managed-entries.tsv`
into `~/.config/opencode`. It never replaces the whole configuration directory.

| Owner    | Paths in `~/.config/opencode`                                                                     | Purpose                                                   |
| -------- | ------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| Dotfiles | `orchestrator/`                                                                                   | Workflow, prompts, permissions and pinned memory adapter  |
| Dotfiles | `profiles/regular/`, `profiles/example/`, `profiles/anthropic/`, `profiles/go/`, `profiles/xing/` | Rendered instructions and model routing                   |
| Dotfiles | `ocx.jsonc`, `opencode.jsonc`, `opencode-mem.jsonc`                                               | Registry, common plugins/MCPs and memory storage settings |
| Dotfiles | `tui.jsonc`                                                                                       | Theme, interaction and notification defaults              |
| OCX      | `.ocx/`, `plugins/`, `package.json`, `.gitignore`                                                 | Component receipts, generated code and dependencies       |
| OCX      | `profiles/default/`                                                                               | Internal initial profile; never selected by the shell     |

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

The installer links the managed entries and refreshes `regular`, `example`,
`anthropic`, `go` and `xing`. Custom profiles and payloads remain untouched.
Re-running the installer is supported and leaves session and memory data
alone.

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

| Command        | Result                                |
| -------------- | ------------------------------------- |
| `opencode`     | Run `ocx opencode` with `OCX_PROFILE` |
| `oc`           | Short form of `opencode`              |
| `oc:regular`   | Select `regular` explicitly           |
| `oc:example`   | Select `example` explicitly           |
| `oc:anthropic` | Select `anthropic` explicitly         |
| `oc:go`        | Select `go` explicitly                |
| `oc:xing`      | Select `xing` explicitly              |

`opencode/env.zsh` declares the default `OCX_PROFILE=regular`. Zed's ACP also
selects `regular`. A host that spawns the binary itself uses
`bin/opencode-profile`, which launches OpenCode directly with the chosen
profile's `OPENCODE_CONFIG` layered over the global configuration. The adapter
supplies the Mise tool environment and Homebrew paths to OpenCode and its
MCP/LSP/shell subprocesses, including when a GUI host starts without a
login-shell `PATH`. It skips automatic dependency preparation; installation
remains part of the normal Mise setup.

### The desktop app

`opencode-desktop` embeds the runtime rather than spawning a CLI, and reads the
same `~/.config/opencode` the shell does: the MCP servers, the plugin list, the
orchestrator and the permissions all arrive already managed. It has no profile
selector and, opened from the Dock, inherits no environment, so
`OPENCODE_CONFIG` never reaches it and nothing would carry the routing the
profiles own.

`opencode/opencode.jsonc` therefore carries the default profile's payload in a
`// generated: default-profile` block that `_scripts/render-opencode-profiles`
writes from `profiles/_routing.tsv` and `opencode/env.zsh`. It is a floor, not a
second declaration: `OPENCODE_CONFIG` merges a profile **over** this file, so
`oc:anthropic`, `oc:go` and `oc:xing` keep replacing every route, and the CLI
behaves exactly as before. Change a route in `_routing.tsv` and rerun the
renderer; never edit between the markers.

Its own window and session state lives in `~/Library/Application Support`,
which is machine-local and untracked, the way every other app's window state is.

The TUI uses Catppuccin Macchiato, `ctrl+x` as leader, `ctrl+p` for commands,
accelerated scrolling, a blinking block cursor and silent notifications.

### Models and roles

<!-- generated: profile-routing -->

| Role       | `regular`                      | `example`                      | `anthropic`                            | `go`                                 | `xing`                                   |
| ---------- | ------------------------------ | ------------------------------ | -------------------------------------- | ------------------------------------ | ---------------------------------------- |
| Default    | `openai/gpt-6-astra`           | `openai/gpt-6-astra`           | `anthropic/claude-fable-5-1`           | `opencode-go/kimi-k3`                | `kimi-for-coding/k3`                     |
| Small      | `openai/gpt-5.6-luna`          | `openai/gpt-5.6-luna`          | `anthropic/claude-opus-5`              | `opencode-go/glm-5.3-flash`          | `zai-coding-plan/glm-5.3-flash`          |
| Plan       | `openai/gpt-6-astra` (`xhigh`) | `openai/gpt-6-astra` (`xhigh`) | `anthropic/claude-fable-5-1` (`xhigh`) | `opencode-go/kimi-k3` (`max`)        | `kimi-for-coding/k3` (`max`)             |
| Build      | `openai/gpt-6-astra` (`xhigh`) | `openai/gpt-6-astra` (`xhigh`) | `anthropic/claude-fable-5-1` (`xhigh`) | `opencode-go/kimi-k3` (`max`)        | `kimi-for-coding/k3` (`max`)             |
| Coder      | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) | `anthropic/claude-opus-5` (`high`)     | `opencode-go/glm-5.3` (`high`)       | `zai-coding-plan/glm-5.3` (`high`)       |
| Explore    | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) | `anthropic/claude-opus-5` (`high`)     | `opencode-go/glm-5.3-flash` (`high`) | `zai-coding-plan/glm-5.3-flash` (`high`) |
| Researcher | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) | `anthropic/claude-opus-5` (`high`)     | `opencode-go/glm-5.3-flash` (`high`) | `zai-coding-plan/glm-5.3-flash` (`high`) |
| Scribe     | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) | `anthropic/claude-opus-5` (`high`)     | `opencode-go/glm-5.3` (`high`)       | `zai-coding-plan/glm-5.3` (`high`)       |
| Reviewer   | `openai/gpt-5.6-luna` (`high`) | `openai/gpt-5.6-luna` (`high`) | `anthropic/claude-opus-5` (`high`)     | `opencode-go/glm-5.3` (`high`)       | `zai-coding-plan/glm-5.3` (`high`)       |

<!-- generated-end -->

In every profile `small_model` is the model its supporting agents already use.
No route asks for a priority tier. `openai/gpt-5.6-luna-fast` and
`anthropic/claude-opus-5-fast` are the same models as the IDs above, with the
same variants and the same context limit, differing only in `serviceTier` and
costing twice as much.

`regular` is the active profile; `example` starts with identical routing and
preserves the structure for future customization. Plan/build coordinates the
work. Coder implements and verifies, reviewer checks a supplied focus, scribe
writes documentation, explore investigates code and researcher retrieves
external facts. Supporting roles are used when useful, not as mandatory stages.

A profile exists for the providers it reaches, and that is the whole of what
separates the five: the shared policy, the agents and their roles are
identical. `anthropic` mirrors the two tiers of `regular`, with Claude Fable
5.1 over plan and build and Claude Opus 5 everywhere else; it resolves only
while the Anthropic auth plugin below loads. `claude-fable-5-1` is the current
Fable: `claude-fable-5` is a separate, older model at the same price rather
than an alias for it. `go` spends the opencode-go plan where a
role judges and saves it where a role mostly reads: Kimi K3 orchestrates, GLM
5.3 writes and reviews, GLM 5.3 Flash explores and researches. Kimi K3
publishes `max` alone, which is why plan and build do not say `xhigh` there.

`xing` is that same split bought direct, and the one profile created for two
providers: Kimi K3 from the Kimi For Coding subscription orchestrates, and GLM
5.3 and GLM 5.3 Flash from the Z.AI Coding Plan do the writing and the reading.
The two subscriptions are bought separately and neither publishes the other's
models, so no single provider can serve this routing. See
[coding-plan providers](#coding-plan-providers) for what the two credentials
are and which endpoint each reaches.

A root runs at most three children with explicit focuses and non-overlapping
writer ownership. Corrections resume the same child. Reviews use a source
snapshot and have no fixed round count. Plan saves do not trigger reviews.
Memory is consolidated in the root execution without auxiliary LLM sessions.
Git coders receive a retained, ignored artifact directory inside their checkout
for diagnostics and downloads; see [artifacts and snapshots](orchestrator/README.md#artifacts-and-review-snapshots).
See [runtime behavior and recovery](orchestrator/README.md) and the
[orchestration contract](ORCHESTRATION.md).

### Anthropic provider

OpenCode ships no Anthropic provider. Without a plugin, `opencode auth list`
reports the stored Anthropic OAuth credential and `opencode models anthropic`
still answers `Provider not found`, so every `anthropic/*` route resolves to
nothing. `opencode.jsonc` pins `@ex-machina/opencode-anthropic-auth` for that
reason.

Its two release lines share one npm name and are not cross-compatible: `1.x` on
the `latest` tag is the OpenCode v1 plugin declared under the `plugin` key, and
`2.x` on `next` is the OpenCode v2 one declared under `plugins`. The pin follows
`npm:opencode-ai` in `mise/config.toml`; loading the wrong line fails with
`must default export an object with server()` and leaves the provider missing
rather than reporting a credential problem.

### Coding-plan providers

`xing` needs no plugin: OpenCode ships both of its providers and authenticates
each from the environment, so the two keys belong in `.localrc` beside the
others. `kimi-for-coding/*` reads `KIMI_API_KEY` and reaches
`api.kimi.com/coding/v1`; `zai-coding-plan/*` reads `ZHIPU_API_KEY` and reaches
`api.z.ai/api/coding/paas/v4`. Both are subscription endpoints rather than
metered ones, which is why `opencode models --verbose` reports zero cost for
every model in them.

One key name serves four providers, and that is the trap worth knowing before
editing a `zai*` route. `ZHIPU_API_KEY` also feeds `zhipuai-coding-plan`, whose
catalog is nearly identical but whose endpoint is `open.bigmodel.cn`, and the
metered `zai` and `zhipuai` pair. `opencode auth list` shows all four as
configured because it only observes that the variable is set; a key issued by
one platform is rejected by the other's endpoint at request time, and the
routing table is the only place that choice is recorded.

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

Every profile enables native language servers through `lsp: true` in the shared
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

Deleting it once is not the end of it, because the failure feeds itself. Argent
tears a failed boot down with `emu kill`, and a cold boot carries no
`-no-snapshot-save`, so the emulator obeys that shutdown by writing a
`default_boot` from whatever half-started guest it had. The next boot restores
that, cannot use it, and is torn down in turn. The snapshot on disk carries no
reliable sign of which kind it is — a half-started guest and a plain lock screen
both save a small `screenshot.png` — so the failing boot is the signal, and
deleting the snapshot is the response to it rather than to anything visible
beforehand.

An emulator that boots through Argent arrives asleep: `dumpsys power` reports
`mWakefulness=Asleep`, and the first-frame probe passes on the all-black screen
that produces. Screenshots are black and the UI tree is a bare `ROOT Screen`
until the device is woken, which reads as a broken emulator and is not one.
Wake it before describing or tapping anything.

### Updating an app without clearing its data

`reinstall-app` is the only install Argent exposes, and it says what it does:
the previous installation is removed first "so app data and runtime permissions
are cleared". There is no flag that keeps them. A retest that depends on state
the app already holds therefore cannot go through the MCP at all, and the
`adb install -r` that does keep it is a coder's ordinary shell command — the
runtime permits it, and only a task that scopes device work to Argent does not.

`ANDROID_HOME` and the SDK tool directories come from `android-studio/_sdk.sh`,
which `path.zsh` and `bin/opencode-profile` both ask, so `adb` is on PATH for a
GUI-hosted session and a login shell alike. Two failures are worth recognizing
rather than rediscovering: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means the new
APK carries a different signature and only an uninstall will take it, which is
the data loss the update was avoiding; `INSTALL_FAILED_VERSION_DOWNGRADE` means
the new `versionCode` is lower and `-d` allows it. `dumpsys package <id>` proves
the outcome, because an update leaves `firstInstallTime` alone and moves
`lastUpdateTime`.

### A locked device makes `describe` slow, not broken

`describe` prefers Argent's own `android-devtools` helper and falls back to
`uiautomator`. The helper is an app, and an Android device that has a PIN and
has not been unlocked since boot refuses to start one that is not Direct Boot
aware. `logcat` carries a `SecurityException` from `startInstrumentation`
saying `com.argent.androiddevtools` is not encryption aware. Argent does not
read that as fatal, so every call waits out the helper's readiness budget
before falling back, and the fallback sometimes loses the race and reports
`Failed to parse uiautomator dump output`. Measured on one AVD locked and
another unlocked: thirty-one seconds through `uiautomator` against one and two
tenths through `android-devtools`. Unlocking past the keyguard is the fix, and
until then the thirty seconds belong to the keyguard rather than to the tool or
the app.

Coder preserves explicit permissions for configured MCP namespaces; a server
alone does not grant access. These permissions do not override native tool
boundaries or authorize remote changes. Build/plan, reviewer, explore and
researcher retain their reviewed read-only tool allowlist. Supporting a new MCP
in those roles requires reviewing its query operations in the runtime.

Tracker retrieval reaches the read-only roles through the `gh`/`glab` queries
they already hold. A project that registers its own tracker MCP does not widen
that: its tools stay outside the reviewed allowlist, so reading through it is a
coder operation with explicit MCP permission, and creating or changing tracker
data is one regardless. Unknown tools are denied even if the server describes
them as read-only.

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
enough either, because a desktop host cannot see that repair: a host that reads
`OPENCODE_DISABLE_EXTERNAL_SKILLS` from its own environment goes on to hide
every skill whose path contains `.agents/` or `.claude/`, so its slash menu
lists no project skills while the agent can still load all of them.

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
1. Name the providers it was created for in `tests/opencode_install_test.sh`.
   No row states that, so nothing else refuses a route borrowed from another
   profile.
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

| State                      | Doctor                          | Why it accumulates                                                                                                     |
| -------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Worktree processes         | Reported, repaired with `--fix` | A command an agent started outlives the session that started it                                                        |
| The `event` table          | Reported, repaired with `--fix` | An append-only replication log for remote workspaces, with no retention                                                |
| Stale `workspace` rows     | Reported, repaired with `--fix` | A row outlives its directory, and a retired adapter fails every server start                                           |
| Stranded sessions          | Reported, repaired with `--fix` | A session names a `workspace` row that is gone, so it can be neither deleted nor archived                              |
| Stale session snapshots    | Reported, repaired with `--fix` | A snapshot shadows the directory its `core.worktree` names, and keeps collecting garbage after it goes                 |
| Idle delegation artifacts  | Reported, repaired with `--fix` | A delegation's evidence directory outlives the work, and nothing else can tell evidence from build output              |
| Idle worktree checkouts    | Reported, repaired with `--fix` | A retired session's checkout keeps its node_modules and build output, and no other condition owns the directory itself |
| An untracked global config | Reported only                   | OpenCode reads `opencode.json` as readily as the managed `opencode.jsonc`                                              |
| Log files                  | Reported, repaired with `--fix` | CLI and plugin output, and the rotations it leaves behind                                                              |

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
Repairs refuse to run while OpenCode holds the database, so quit the desktop
app and any `opencode` session first. That precondition is also what makes reaping
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
