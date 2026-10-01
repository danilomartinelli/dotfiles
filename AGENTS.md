# Repository guide for coding agents

## Project and owner

This repository is the source of truth for Danilo Martinelli's personal macOS
environment. It declares Homebrew software, Mise-managed runtimes, macOS
defaults, Zsh startup, public shell commands, application configuration, and
idempotent topic installers.

This is operating-system configuration, not an application with a build
artifact or deployment pipeline. Applying it changes the current Mac; develop
against isolated fixtures whenever possible.

Danilo is the sole owner unless a user request says otherwise. Do not invent
reviewers, approvers, teams, or external stakeholders.

## Instructions and documentation

- `AGENTS.md` defines repository-wide agent workflow.
- `CODING_STANDARDS.md` defines normative implementation and validation rules.
- `README.md` is the human-facing installation, operation, and command guide.
- `opencode/README.md` owns OpenCode configuration details.
- `agents/instructions.md` is a payload: every coding agent on this machine
  reads it as its global `AGENTS.md`. It does not replace this root guide.

Explicit user instructions take precedence. For a file below a nested
`AGENTS.md`, also follow the closest applicable instructions.

## Repository map

```text
dotfiles/
├── bin/                  # Public executables added to PATH
├── functions/            # Public Zsh autoload functions
├── tests/                # Isolated behavioral and contract tests
├── _scripts/             # Private setup, linking, and discovery machinery
├── _macos/               # macOS defaults catalog and adapters
├── <topic>/              # Tool-specific shell files and optional installer
├── Brewfile              # Homebrew declarations
├── mise/config.toml      # Runtime and language-package CLI declarations
├── mise/mise.lock        # Generated Mise resolution lock
└── .localrc.example      # Secret-free machine-local template
```

Visible top-level directories are topics unless `_scripts/topic-catalog`
classifies them as reserved. `bin/`, `docs/`, `functions/`, and `tests/` are not
topics; hidden and underscore-prefixed names are excluded from discovery.

## Start every task safely

1. Inspect the checkout before editing:

   ```bash
   git -c core.fsmonitor=false status --short --branch
   git -c core.fsmonitor=false diff
   ```

1. Preserve all unrelated tracked and untracked work. Never discard user work
   merely to obtain a clean tree.

1. Locate the owning source, adapter, fixture test, and documentation with
   `rg` and `rg --files`.

1. Distinguish repository source, installed machine state, and live external
   state. A source diff does not prove that configuration was applied.

1. Read only secret-free examples such as `.localrc.example`. Never inspect or
   print `.localrc`, auth stores, private keys, kubeconfigs, generated Git
   identity, or account-specific state.

## Sources of truth

| Concern                                         | Source                       |
| ----------------------------------------------- | ---------------------------- |
| Homebrew taps, formulae, casks, fonts, MAS apps | `Brewfile`                   |
| README software catalog tables                  | rendered from declarations   |
| Runtimes and language-package CLIs              | `mise/config.toml`           |
| Mise versions and checksums                     | `mise/mise.lock` (generated) |
| macOS preferences                               | `_macos/defaults.tsv`        |
| Dock layout                                     | `dock/_layout.tsv`           |
| Post-bootstrap checklist                        | `_scripts/_checklist.tsv`    |
| Topic discovery and load classes                | `_scripts/topic-catalog`     |
| Setup orchestration                             | `_scripts/setup`             |
| Global coding-agent instructions                | `agents/instructions.md`     |
| Trusted roots for direnv and Mise               | `_scripts/trusted-roots`     |
| Public lifecycle and commands                   | `README.md`                  |
| Coding and validation rules                     | `CODING_STANDARDS.md`        |

Never edit `mise/mise.lock` manually. Regenerate it with `mise lock --global`
from the repository root and review the generated diff narrowly. `dot` installs
with `--locked` and never writes it.

## Core implementation contracts

### Topics and installers

A topic may contain `install.sh`, direct `*.symlink` entries, `path.zsh`,
`aliases.zsh`, `env.zsh`, `completion.zsh`, and other visible `.zsh` files.

- Installers are executable, non-interactive, idempotent, and safe during both
  bootstrap and update.
- Source `_scripts/installer-preamble.sh` immediately after shell error-mode
  setup and use its guards, messages, and linking wrapper.
- Read every tab-separated catalog *file* through `catalog_each_row` from
  `_scripts/catalog.sh`, which the preamble sources. No such consumer writes
  its own `read` loop. A catalog arriving as a command's stdout, such as
  `_scripts/topic-catalog` output, is read directly.
- Do not duplicate checkout resolution, Darwin detection, dependency hints,
  output conventions, or conflict handling in individual topics.
- Only `*.symlink` files and directories are linked automatically.
- Keep shell startup safe to source repeatedly and preserve catalog ordering.

### Dependencies

- Put system binaries, libraries, applications, fonts, MAS apps, and taps in
  `Brewfile`.
- Put npm, PyPI/pipx, Ruby gem, Go module, and comparable CLIs in
  `mise/config.toml`.
- Add a third-party tap to both `Brewfile` and the narrow trust flow in
  `homebrew/_bundle.sh`. `tests/documentation_test.sh` holds the two lists to
  each other, because trust is not expressible in a Brewfile and neither list
  can derive the other.
- Give every declaration a trailing comment; it is the description
  `_scripts/render-software-catalog` renders into the README catalog tables.
  Run the renderer with the declaration change.
- Do not run broad package-manager repair commands such as `npm audit fix`.

### Coding agents

Claude Code, Codex, Kimi Code and OpenCode run from Mise; Conductor, the Claude
desktop app and the OpenCode desktop app are casks. An agent topic links only
credential-free files:

- `claude/settings.json`, `conductor/settings.toml` and `kimi/tui.toml` are
  linked files their apps also write, as Zed's settings are. A diff in one may
  be the app's; keep or discard it deliberately rather than reverting it as
  noise.
- Codex's and Kimi Code's `config.toml` stay machine-local: they record project
  trust, plugin state and provider credentials.
- `agents/install.sh` links `agents/instructions.md` into every agent's own
  directory. Change the shared instructions there, once.

`opencode/opencode.jsonc` stays in OpenCode v1 syntax: the desktop app runs v1,
and Conductor's bundled OpenCode v2 reads the same file. Move the
`@ex-machina/opencode-anthropic-auth` pin only with `npm:opencode-ai`; its two
release lines serve the two OpenCode majors. Validate a model ID and its
variants against the live `opencode models <provider> --verbose` catalog.
Variants are model-specific, and `variant` is the only reasoning knob an agent
accepts: `reasoningEffort` and `textVerbosity` are provider option names that
OpenCode discards without a word.

`_scripts/trusted-roots` is the one declaration of the trusted roots. direnv's
whitelist is rendered from it by `direnv/install.sh` and Mise receives it
through `mise/mise.zsh`; a project outside those roots keeps its explicit
`direnv allow` or `mise trust`.

## Editing and simplification

- Follow `CODING_STANDARDS.md` and the neighboring file's dialect.
- Prefer a small, explicit change over broad speculative refactoring.
- Preserve behavior unless the request or an evidenced defect requires a
  contract change.
- Remove dead or duplicate code only after finding all references and extending
  focused coverage for the retained path.
- Keep public adapters small and place shared behavior in the private owner.
- Add or update fixtures for behavior changes and documentation contracts.
- Do not edit generated files or machine-local runtime state.

## Validation

Do not run `_scripts/bootstrap`, `dot`, `set-defaults`, Homebrew mutation,
credential creation, app-opening setup, or destructive Git utilities merely to
validate source changes.

Use the focused matrix in `CODING_STANDARDS.md`, then expand in proportion to
risk. Repository-wide changes require every safe test:

```bash
_scripts/test
```

`_scripts/test` owns discovery, ordering, and the pass/fail verdict, and names
every suite that failed. Pass a pattern — `_scripts/test link_config` — to run
one row of the focused matrix.

Run all applicable static checks from `CODING_STANDARDS.md`. At minimum, review
`git diff --check`; lint and format changed Shell, Zsh, Markdown, JSON/JSONC,
and Nix files with their declared repository tools. Never run `shfmt` on
Zsh-only syntax.

## Documentation ownership

- Keep `README.md` self-contained for installation, normal operation, public
  commands, and dependency discovery.
- Keep this file concise and actionable for automated contributors.
- Keep normative style, testing, and delivery rules in
  `CODING_STANDARDS.md`.
- Keep subsystem maintenance and troubleshooting in the owning topic README.
- Do not add generic license, contribution, changelog, support, or governance
  sections unsupported by this personal repository.

`tests/documentation_test.sh` enforces coverage of public commands, functions,
aliases, package declarations, and installer helpers. Update documentation in
the same change as the public surface.

## Security boundaries

- Secrets belong only in gitignored `.localrc` with mode `600` or an
  appropriate system credential store.
- Generated Git identity, SSH private keys, SOPS identities, kubeconfigs, auth
  receipts, agent runtime state, and account identifiers are machine-private.
- `ssh-key-create` and `sops-key-create` are the only key-creation paths in the
  repository. Any installer may repair safe links, directories, and
  permissions, and may report that a key is missing by naming the command that
  creates it; none runs a generator. They share the guards in
  `_scripts/key-provisioning.sh`.
- Tracked Zed, OpenCode, Claude Code, Conductor and Kimi Code configuration
  must not contain plaintext credentials or pretend that settings interpolate
  `$VARIABLE` when they do not.
- Resolve the exact target and confirm user authorization before destructive or
  remote-changing operations.

## Commit and publication workflow

Commit or push only when explicitly requested.

1. Review `git status`, `git diff`, and `git diff --check`.

1. Stage only confirmed task paths.

1. Use a concise imperative commit message consistent with repository history.

1. Push the requested branch explicitly, such as `git push origin main`.

1. Verify cleanliness and synchronization:

   ```bash
   git -c core.fsmonitor=false status --short --branch
   git -c core.fsmonitor=false rev-list --left-right --count origin/main...main
   ```

If Git reports `fsmonitor_ipc__send_query` errors, repeat inspection with
`-c core.fsmonitor=false`; do not reset or recreate the checkout. The usual
source of those errors is a daemon that died with the worktree it watched, and
`git/gitconfig.worktree.symlink` now keeps linked worktrees out of fsmonitor
for that reason, so treat a recurrence in a main working tree as new
information rather than the known case.

## Definition of done

A task is complete only when the requested behavior is implemented in its
owning source, focused and repository-wide validation are green as required,
documentation matches behavior, the diff contains no unrelated work or secret
material, and every explicitly requested push is verified on the target branch.
