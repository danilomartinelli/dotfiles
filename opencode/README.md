# OpenCode via OCX

This topic installs the OpenCode CLI through Mise, uses OCX to assemble its
global workspace, and keeps the editable parts of that workspace under version
control.

The active configuration directory is `~/.config/opencode`. The repository does
not replace that directory as a whole: it links only the paths that should be
reviewed and evolved in dotfiles while leaving generated OCX state local.

## Ownership

| Owner    | Paths in `~/.config/opencode`                          | Purpose                                                 |
| -------- | ------------------------------------------------------ | ------------------------------------------------------- |
| Dotfiles | `agents/`, `commands/`, `skills/`, `tools/`            | Editable workspace behavior installed by OCX            |
| Dotfiles | `profiles/boost/`, `profiles/regular/`, `profiles/go/` | Versioned profile instructions and model configuration  |
| Dotfiles | `ocx.jsonc`, `opencode.jsonc`, `opencode-mem.jsonc`    | Global OCX, OpenCode, and memory plugin configuration   |
| Dotfiles | `tui.jsonc`                                            | TUI theme, interaction, and notification defaults       |
| OCX      | `.ocx/`, `plugins/`                                    | Installation receipt and generated plugin code          |
| OCX      | `package.json`, `.gitignore`                           | Generated runtime dependencies and ignore rules         |
| OCX      | `profiles/default/`                                    | Initial generated profile; the shell does not select it |

Do not copy the OCX-owned paths into this repository. They change as OCX
installs or updates components and are not intended for manual maintenance.

`opencode/_managed-entries.tsv` is the catalog behind the dotfiles rows above.
It declares every entry and profile the installer links, and both
`tests/opencode_install_test.sh` and `tests/documentation_test.sh` derive their
expectations from it. Adding or removing a managed entry starts there.

The three profile directories are rendered, not written by hand.
`opencode/profiles/_shared/` holds the policy every profile shares and
`opencode/profiles/_routing.tsv` holds the model routing that distinguishes
them; `_scripts/render-opencode-profiles` composes the two into the payloads
the installer links. Edit the sources and rerun the renderer rather than
editing a profile directory.

## Install or refresh

Run the topic installer directly:

```bash
opencode/install.sh
```

Normal bootstrap and `dot` updates also run it. The installer:

1. Requires the Mise-provided `opencode` and `ocx` commands.
1. Initializes the global OCX configuration.
1. Registers `https://registry.kdco.dev` as `kdco`.
1. Installs the `kdco/workspace` component set when its receipt is absent.
1. Links every entry declared in `opencode/_managed-entries.tsv` into
   `~/.config/opencode`, replacing each generated target instead of backing it
   up.
1. Creates `regular`, clones `go` and `boost` from it with OCX, then replaces
   each generated profile directory with its repository link. The clone copies
   only `ocx.jsonc` and the link discards even that, so every byte OpenCode
   reads comes from this repository.

Re-running the installer is supported. Once the workspace receipt exists, it
does not reinstall the component bundle, so local edits exposed through the
managed links are preserved. It refreshes the three managed profiles without
replacing `.ocx`, `plugins`, `package.json`, `.gitignore`, or
`profiles/default`.

Refreshing a profile calls `ocx profile remove` before `ocx profile add`, and
after the first install that path is a symbolic link into this checkout. `ocx`
removes a profile with a single recursive remove, which unlinks the link rather
than descending into it, so the versioned payload behind it is untouched.
Verified against `ocx` 2.0.15, the version `mise/config.toml` declares.
Re-verify it when that version changes: a release that deleted a profile's
contents would take repository files with it, and `configure_profile` would
then have to stop calling `ocx profile remove` for an already-linked profile.
`tests/opencode_install_test.sh` holds its `ocx` fake to the verified behaviour
before any scenario points that fake at the checkout.

## Use OpenCode

Open a new Zsh session or run `reload!` after changing the shell files.

| Command      | Result                                                        |
| ------------ | ------------------------------------------------------------- |
| `opencode`   | Run `ocx opencode` with the profile selected by `OCX_PROFILE` |
| `oc`         | Short form of `opencode`                                      |
| `oc:boost`   | Run the `boost` profile explicitly                            |
| `oc:regular` | Run the `regular` profile explicitly                          |
| `oc:go`      | Run the `go` profile explicitly                               |

`opencode/env.zsh` exports `OCX_PROFILE=regular`, so `opencode` and `oc` use the
`regular` profile by default. Explicit profile aliases pass `-p` and do not
change that default.

The managed TUI keeps OpenCode aligned with the terminal stack: Catppuccin
Macchiato, `ctrl+x` as the leader, `ctrl+p` for the command list, accelerated
mouse scrolling, a blinking block cursor, and notifications without sound.
Plugins remain in `opencode.jsonc`, which is their single configuration owner.

### Profile contract and model routing

OCX has no profile inheritance. Nothing above a profile layers into its
`ocx.jsonc` or `opencode.jsonc`, so every shared key has to be physically
present in every profile, and `ocx profile add --clone` copies only `ocx.jsonc`
at creation time. The layering therefore happens in this repository:
`profiles/_shared/` states the instructions, the OCX policy, the permissions,
the MCP servers, and the researcher's read-oriented GitLab policy exactly once,
and each profile contributes only the routing rows below.

| Role       | `regular`                     | `go`                                  | `boost`                           |
| ---------- | ----------------------------- | ------------------------------------- | --------------------------------- |
| Default    | `openai/gpt-5.6-terra`        | `opencode-go/grok-4.6`                | `openai/gpt-5.6-sol`              |
| Small      | `openai/gpt-5.6-luna`         | `opencode-go/gpt-5.6-luna`            | `kimi-for-coding/k3`              |
| Plan       | `openai/gpt-5.6-terra` (high) | `opencode-go/grok-4.6` (`xhigh`)      | `anthropic/claude-opus-5` (`max`) |
| Build      | `openai/gpt-5.6-terra` (high) | `opencode-go/glm-5.3` (`max`)         | `openai/gpt-5.6-sol` (`max`)      |
| Coder      | `openai/gpt-5.6-luna` (high)  | `opencode-go/kimi-k3` (`max`)         | `openai/gpt-5.6-luna` (`xhigh`)   |
| Explore    | `openai/gpt-5.6-luna` (low)   | `opencode-go/gpt-5.6-luna` (`max`)    | `kimi-for-coding/k3` (`max`)      |
| Researcher | `openai/gpt-5.6-sol` (high)   | `opencode-go/qwen3.8-max`             | `opencode-go/grok-4.6` (`xhigh`)  |
| Scribe     | `openai/gpt-5.6-luna` (low)   | `opencode-go/minimax-m3` (`thinking`) | `minimax-coding-plan/MiniMax-M3`  |
| Reviewer   | `openai/gpt-5.6-sol` (high)   | `opencode-go/deepseek-v4-pro` (`max`) | `zai-coding-plan/glm-5.3` (`max`) |

`go` stays entirely on the OpenCode Go provider. `boost` is quality-first and
has no cost ceiling: it combines direct Anthropic, OpenAI, Kimi, MiniMax, and
Z.AI routes with OpenCode Go's Grok. Claude, Sol, Luna, Kimi, Grok, and
GLM use their highest valid configured reasoning variants; MiniMax uses its
provider default for the writing-focused `scribe` role.

### Trusted project integrations

The `regular` profile is intended for trusted projects. OCX excludes only
`CLAUDE.md`, so project-level OpenCode configuration, MCP servers, and
permissions remain available. Its researcher agent extends the global
read-oriented `gh` policy with equivalent `glab` routes for repositories, merge
requests, issues, releases, CI, search, and the API.

The profile `include` list stays empty because OCX already merges the trusted
project's `AGENTS.md`, OpenCode configuration, and `.opencode/` payload. The
shell keeps `OPENCODE_DISABLE_PROJECT_CONFIG=true` so the OpenCode child does
not discover those sources a second time. It exports
`OPENCODE_DISABLE_EXTERNAL_SKILLS=false` to retain compatible `.agents/skills`
discovery, while `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=true` continues to omit
`.claude/skills`.

The profile also declares Linear's remote MCP with `linear_*` tools allowed, and
the server is enabled, so the first connection requires Linear authentication.
Set `mcp.linear.enabled` to `false` in
`opencode/profiles/regular/opencode.jsonc` to turn it off again.

Zed's ACP integration is separate from these interactive aliases and starts
OpenCode through OCX with the `boost` profile explicitly.

## Edit the global workspace

Edit the repository source, not the link under `~/.config/opencode`:

- Agent prompts: `opencode/agents/`
- Commands: `opencode/commands/`
- Skills: `opencode/skills/`
- Shared instructions: `opencode/tools/`
- Global OCX registry: `opencode/ocx.jsonc`
- Global OpenCode configuration: `opencode/opencode.jsonc`
- OpenCode memory plugin configuration: `opencode/opencode-mem.jsonc`
- Global TUI configuration: `opencode/tui.jsonc`
- Shared profile policy: `opencode/profiles/_shared/`
- Model routing: `opencode/profiles/_routing.tsv`

Changes are immediately visible through the symbolic links. Review the Git diff
before keeping changes produced by an OCX component update.

## Edit or add a profile

A profile directory holds three rendered files:

- `AGENTS.md` and `ocx.jsonc`, copied from `profiles/_shared/`.
- `opencode.jsonc`, composed from `profiles/_shared/opencode.jsonc` and the
  profile's rows in `profiles/_routing.tsv`.

To change what every profile shares, edit `profiles/_shared/`. To change one
profile's routing, edit its rows in `profiles/_routing.tsv`. Either way, render
the result:

```bash
_scripts/render-opencode-profiles
```

The routing table carries one row per profile and role, with `-` omitting a
key. `default` and `small` name the profile's `model` and `small_model` and
take a model only; the remaining roles are the agents declared in
`profiles/_shared/opencode.jsonc`. The renderer refuses a row that names an
unknown profile or agent, a duplicate row, a role the shared base declares and
the profile never routes, and a non-numeric temperature.

To add another profile derived from the trusted-project baseline:

1. Add its rows to `opencode/profiles/_routing.tsv`.
1. Add a `profile` row to `opencode/_managed-entries.tsv` below the `regular`
   row, naming `regular` as its clone source. The installer and both test
   suites pick it up from there.
1. Run `_scripts/render-opencode-profiles` to write the profile directory.
1. Add its `oc:<name>` shortcut to `opencode/aliases.zsh` and document the
   profile in this file, `README.md`, and `AGENTS.md`;
   `tests/documentation_test.sh` fails until all four exist.
1. Validate every model and variant against the live model catalog, run the
   installer, and verify the resulting link.

Nothing else is edited by hand: the shared instructions, OCX policy,
permissions, and MCP configuration come from `profiles/_shared/` unchanged.

## Update OCX components

Use OCX for component updates, then review any changes exposed through the
managed links:

```bash
ocx update --all
git diff -- opencode
tests/opencode_install_test.sh
```

Keep intended updates in the repository. Revert or correct unintended changes
before the next dotfiles update.

## Verify

Run the focused suite:

```bash
tests/opencode_install_test.sh
```

It verifies the shell defaults and aliases, JSON and TUI configuration, that
every profile still matches its composed result, exact model routing, payload
ownership, exact link targets, repeat installation, preservation of runtime
state, and receipt-aware workspace installation.

`_scripts/render-opencode-profiles --check` reports the same drift on its own,
naming each payload that no longer matches its sources.

Inspect the live links when diagnosing a machine-specific issue:

```bash
find "$HOME/.config/opencode" -maxdepth 2 -type l -print
ocx profile list --global
```

Expected managed links are the global entries in the ownership table plus the
`boost`, `regular`, and `go` profile directories, exactly as
`opencode/_managed-entries.tsv` declares them.

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
