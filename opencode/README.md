# OpenCode

The OpenCode CLI (`npm:opencode-ai` in `mise/config.toml`) and the desktop app
(`opencode-desktop` in `Brewfile`) are upstream. This topic owns two files in
`~/.config/opencode`; OpenCode owns everything else there, including the
`package.json`, `bun.lock` and `node_modules` it writes while installing
plugins. The global agent instructions it reads as `AGENTS.md` come from the
`agents` topic, shared with every other coding agent.

| Path in `~/.config/opencode` | Purpose                                      |
| ---------------------------- | -------------------------------------------- |
| `opencode.jsonc`             | Models, MCP servers and plugins              |
| `tui.jsonc`                  | Theme, interaction and notification defaults |

## Install or refresh

```bash
opencode/install.sh
```

Bootstrap and `dot` also invoke this installer. It only links the two files, so
re-running it is harmless. Start a new OpenCode process to load a change; an
existing one keeps the configuration it loaded.

The TUI uses Catppuccin Macchiato, `ctrl+x` as leader, `ctrl+p` for commands,
accelerated scrolling, a blinking block cursor and silent notifications.

## Models

`opencode.jsonc` states `model`, `small_model`, and the `plan` and `build`
agents with their `variant`. The desktop app, opened from the Dock, inherits no
environment and reads only this file, so without these keys it would start with
no model at all.

Each agent names its model beside its variant. Variants are model-specific, and
OpenCode v2, which Conductor runs against this same file, drops a variant that
arrives without a model. Validate a model ID and its variants against the live
catalog before changing them:

```bash
opencode models <provider> --verbose
```

`variant` is the only reasoning knob an agent accepts. `reasoningEffort` and
`textVerbosity` are provider option names that OpenCode discards without a
word.

### Staying on OpenCode v1

OpenCode v2 is published as `@opencode/cli`, beside `opencode-ai`, which still
carries v1. This topic stays on v1 until these hold:

- `@franlol/opencode-md-table-formatter` has a v2 release. Its only hook has no
  v2 equivalent.
- v2 runs language servers. It accepts `lsp: true` and does nothing with it.
- The desktop app ships v2. Until then it reads this same file, which therefore
  has to stay in v1 syntax.

v2 also reads its terminal settings from `cli.json` rather than `tui.jsonc`, so
moving means rewriting that file, and the Anthropic plugin moves to its `2.x`
line under the `plugins` key.

## Anthropic provider

OpenCode ships no Anthropic subscription login. Without a plugin,
`opencode auth list` reports the stored Anthropic OAuth credential and
`opencode models anthropic` still answers `Provider not found`.
`opencode.jsonc` pins `@ex-machina/opencode-anthropic-auth` for that reason.

Its two release lines share one npm name and are not cross-compatible: `1.x` on
the `latest` tag is the OpenCode v1 plugin declared under the `plugin` key, and
`2.x` on `next` is the OpenCode v2 one declared under `plugins`. The pin follows
`npm:opencode-ai` in `mise/config.toml`; loading the wrong line fails with
`must default export an object with server()` and leaves the provider missing
rather than reporting a credential problem.

## Coding-plan providers

Two subscription providers need no plugin: OpenCode ships both and
authenticates each from the environment, so their keys belong in `.localrc`
beside the others. `kimi-code-plan-global/*` reads `KIMI_API_KEY` and reaches
`api.kimi.ai/coding/v1`; `zai-coding-plan/*` reads `ZHIPU_API_KEY` and reaches
`api.z.ai/api/coding/paas/v4`. Both are subscription endpoints rather than
metered ones, which is why `opencode models --verbose` reports zero cost for
every model in them.

One key name serves four providers, and that is the trap worth knowing before
choosing a `zai*` model. `ZHIPU_API_KEY` also feeds `zhipuai-coding-plan`, whose
catalog is nearly identical but whose endpoint is `open.bigmodel.cn`, and the
metered `zai` and `zhipuai` pair. `opencode auth list` shows all four as
configured because it only observes that the variable is set; a key issued by
one platform is rejected by the other's endpoint at request time.

## Code navigation: LSP and CodeGraph

`lsp: true` enables OpenCode's native language servers, which start on demand
for the languages a project contains. Server availability still depends on the
language and its project dependencies. See the
[native LSP guide](https://opencode.ai/docs/lsp/).

CodeGraph is declared through Mise. The MCP configuration runs
`codegraph serve --mcp`, matching `codegraph install --print-config opencode`,
with telemetry disabled; the declaration replaces running the interactive
installer against managed configuration. An index belongs to one checkout and
nothing builds it automatically: the shared agent instructions tell an agent to
run `codegraph init` when `.codegraph/` is missing. `.codegraph/` is ignored
globally by `git/gitignore.symlink`.

## Skills

No skill discovery flag is set, so OpenCode reads `.agents/skills` and
`.claude/skills` from the home directory and from every directory between the
current one and the Git worktree root, alongside project `.opencode/skills`.
Global configuration carries only the MCP servers and plugins above; anything
else a project needs belongs in that project's own `opencode.json`.

## Argent device control

`argent` is declared in `mise/config.toml` and its MCP server in
`opencode.jsonc`, with `DO_NOT_TRACK=1` because its telemetry is on by default.
`argent_debugger-evaluate` evaluates arbitrary JavaScript inside the running
app, so a project that wants a narrower boundary states it in its own
configuration:

```json
{
  "permission": {
    "argent_*": "allow",
    "argent_debugger-evaluate": "ask"
  }
}
```

Never run `argent init`. It writes its own editor registration and would leave
an untracked configuration beside the managed one. The declaration above
replaces it.

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
a failure only through the MCP is the integration.

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
`adb install -r` that does keep it is an ordinary shell command, which only a
task that scopes device work to Argent rules out.

`ANDROID_HOME` and the SDK tool directories come from `android-studio/_sdk.sh`,
which `android-studio/path.zsh` asks, so `adb` is on PATH in every shell an
agent starts from. Two failures are worth recognizing
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
