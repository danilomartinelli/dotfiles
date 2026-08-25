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
| Dotfiles | `ocx.jsonc`, `opencode.jsonc`                          | Global OCX registry and merged OpenCode configuration   |
| OCX      | `.ocx/`, `plugins/`                                    | Installation receipt and generated plugin code          |
| OCX      | `package.json`, `.gitignore`                           | Generated runtime dependencies and ignore rules         |
| OCX      | `profiles/default/`                                    | Initial generated profile; the shell does not select it |

Do not copy the OCX-owned paths into this repository. They change as OCX
installs or updates components and are not intended for manual maintenance.

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
1. Links the dotfiles-owned global entries into `~/.config/opencode`.
1. Recreates `boost`, `regular`, and `go`, then replaces each generated profile
   directory with its repository link.

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

The `regular` profile is intended for trusted projects. OCX excludes only
`CLAUDE.md`, so project-level OpenCode configuration, MCP servers, and
permissions remain available. Its researcher agent extends the global
read-oriented `gh` policy with equivalent `glab` routes for repositories, merge
requests, issues, releases, CI, search, and the API.

The profile also declares Linear's remote MCP with `linear_*` tools allowed,
but keeps the server disabled. Set `mcp.linear.enabled` to `true` in
`opencode/profiles/regular/opencode.jsonc` when it should become available; the
first connection will require Linear authentication.

Zed's ACP integration is separate from these interactive aliases and starts the
Mise-managed OpenCode binary directly.

## Edit the global workspace

Edit the repository source, not the link under `~/.config/opencode`:

- Agent prompts: `opencode/agents/`
- Commands: `opencode/commands/`
- Skills: `opencode/skills/`
- Shared instructions: `opencode/tools/`
- Global OCX registry: `opencode/ocx.jsonc`
- Global OpenCode configuration: `opencode/opencode.jsonc`

Changes are immediately visible through the symbolic links. Review the Git diff
before keeping changes produced by an OCX component update.

## Edit or add a profile

Each managed profile contains:

- `AGENTS.md` for profile-specific instructions.
- `ocx.jsonc` for OCX profile behavior.
- `opencode.jsonc` for models, agents, MCP servers, and OpenCode settings.

To change an existing profile, edit its directory below `opencode/profiles/`.

To add another managed profile:

1. Run `ocx profile add <name> --global` to generate its initial files.
1. Add those three files under `opencode/profiles/<name>/`.
1. Add `configure_profile <name>` to `opencode/install.sh`.
1. Add the profile and its shell entrypoint to
   `tests/opencode_install_test.sh` and this document.
1. Run the installer and verify the resulting link.

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

It verifies the shell defaults and aliases, JSON configuration, payload
ownership, exact link targets, repeat installation, preservation of runtime
state, and receipt-aware workspace installation.

Inspect the live links when diagnosing a machine-specific issue:

```bash
find "$HOME/.config/opencode" -maxdepth 2 -type l -print
ocx profile list --global
```

Expected managed links are the six global entries in the ownership table plus
the `boost`, `regular`, and `go` profile directories.

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
