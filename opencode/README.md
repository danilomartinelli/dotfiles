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
   each generated profile directory with its repository link.

Re-running the installer is supported. Once the workspace receipt exists, it
does not reinstall the component bundle, so local edits exposed through the
managed links are preserved. It refreshes the three managed profiles without
replacing `.ocx`, `plugins`, `package.json`, `.gitignore`, or
`profiles/default`.

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

The installer materializes `regular` first and uses `ocx profile add --clone regular` for both specialized profiles. Their `AGENTS.md` instructions and
`ocx.jsonc` policy stay identical to `regular`; permissions, MCP servers, and
the researcher's read-oriented GitLab policy are also preserved. Only model
routing and model-specific options differ.

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

The profile also declares Linear's remote MCP with `linear_*` tools allowed,
but keeps the server disabled. Set `mcp.linear.enabled` to `true` in
`opencode/profiles/regular/opencode.jsonc` when it should become available; the
first connection will require Linear authentication.

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

Changes are immediately visible through the symbolic links. Review the Git diff
before keeping changes produced by an OCX component update.

## Edit or add a profile

Each managed profile contains:

- `AGENTS.md` for profile-specific instructions.
- `ocx.jsonc` for OCX profile behavior.
- `opencode.jsonc` for models, agents, MCP servers, and OpenCode settings.

To change an existing profile, edit its directory below `opencode/profiles/`.

To add another profile derived from the trusted-project baseline:

1. Run `ocx profile add <name> --clone regular --global` to generate its
   initial files.
1. Add those three files under `opencode/profiles/<name>/`.
1. Add a `profile` row to `opencode/_managed-entries.tsv` below the `regular`
   row, naming `regular` as its clone source. The installer and both test
   suites pick it up from there.
1. Add its `oc:<name>` shortcut to `opencode/aliases.zsh` and document the
   profile in this file, `README.md`, and `AGENTS.md`;
   `tests/documentation_test.sh` fails until all four exist.
1. Keep the shared instructions, OCX policy, permissions, and MCP configuration
   aligned; specialize only the intended profile fields.
1. Validate every model and variant against the live model catalog, run the
   installer, and verify the resulting link.

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

It verifies the shell defaults and aliases, JSON and TUI configuration, cloned
profile policy, exact model routing, payload ownership, exact link targets,
repeat installation, preservation of runtime state, and receipt-aware workspace
installation.

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
