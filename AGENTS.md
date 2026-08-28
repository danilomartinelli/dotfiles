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
- `opencode/README.md` owns detailed OCX/OpenCode procedures.
- `opencode/profiles/*/AGENTS.md` files are versioned profile payloads. They
  configure OpenCode sessions and do not replace this root guide.
- `docs/agents/*.md` record the issue tracker, triage labels, and domain
  documentation conventions that the engineering skills read.

Explicit user instructions take precedence. For a file below a nested
`AGENTS.md`, also follow the closest applicable instructions.

## Agent skills

### Issue tracker

Issues live in GitHub Issues at `danilomartinelli/dotfiles`, driven by the `gh`
CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name. See
`docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md` plus `docs/adr/`. See
`docs/agents/domain.md`.

## Repository map

```text
dotfiles/
├── bin/                  # Public executables added to PATH
├── functions/            # Public Zsh autoload functions
├── tests/                # Isolated behavioral and contract tests
├── docs/agents/          # Issue tracker, triage, and domain conventions
├── _scripts/             # Private setup, linking, and discovery machinery
├── _macos/               # macOS defaults catalog and adapters
├── opencode/             # Dotfiles-owned OpenCode and OCX configuration
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
| Runtimes and language-package CLIs              | `mise/config.toml`           |
| Mise versions and checksums                     | `mise/mise.lock` (generated) |
| macOS preferences                               | `_macos/defaults.tsv`        |
| Topic discovery and load classes                | `_scripts/topic-catalog`     |
| Setup orchestration                             | `_scripts/setup`             |
| OpenCode and OCX workspace                      | `opencode/`                  |
| Public lifecycle and commands                   | `README.md`                  |
| Coding and validation rules                     | `CODING_STANDARDS.md`        |

Never edit `mise/mise.lock` manually. Regenerate it through Mise from the
repository root and review the generated diff narrowly.

## Core implementation contracts

### Topics and installers

A topic may contain `install.sh`, direct `*.symlink` entries, `path.zsh`,
`aliases.zsh`, `env.zsh`, `completion.zsh`, and other visible `.zsh` files.

- Installers are executable, non-interactive, idempotent, and safe during both
  bootstrap and update.
- Source `_scripts/installer-preamble.sh` immediately after shell error-mode
  setup and use its guards, messages, and linking wrapper.
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
  `homebrew/_bundle.sh`.
- Update the README software catalog with every declaration change.
- Do not run broad package-manager repair commands such as `npm audit fix`.

### OpenCode and OCX

`opencode/install.sh` initializes OCX and links only dotfiles-owned entries
into `~/.config/opencode`.

Dotfiles owns `agents/`, `commands/`, `skills/`, `tools/`, `ocx.jsonc`,
`opencode.jsonc`, `tui.jsonc`, and the managed `regular`, `go`, and `boost`
profiles. OCX owns `.ocx/`, `plugins/`, `package.json`, `.gitignore`, and
`profiles/default/`; never copy or version those runtime paths.

The versioned `agents/`, `commands/`, `skills/`, and `tools/` payloads retain
OCX registry checksums. Update them through `ocx update`, do not reformat them
independently, and require `ocx verify --cwd ~/.config/opencode --verbose` to
remain green.

Install `regular` first and clone specialized profiles from it. Keep profile
instructions, permissions, MCP policy, and researcher shell policy aligned;
specialize model routing and model-specific options only.

When a managed entry or profile changes, update these together:

- `opencode/install.sh`
- `opencode/README.md`
- `tests/opencode_install_test.sh`

Validate model IDs and variants against the current live
`opencode models <provider> --verbose --pure` catalog. Variants are
model-specific; do not invent a universal reasoning or performance option.

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
for test_path in tests/*_test.sh; do
  "$test_path"
done
_scripts/test-checkout-root
```

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
  receipts, OCX runtime state, and account identifiers are machine-private.
- The SSH and SOPS installers may repair safe links, directories, and
  permissions; their explicit credential commands are the only key-creation
  paths in those subsystems.
- Tracked Zed and OpenCode configuration must not contain plaintext credentials
  or pretend that settings interpolate `$VARIABLE` when they do not.
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
`-c core.fsmonitor=false`; do not reset or recreate the checkout.

## Definition of done

A task is complete only when the requested behavior is implemented in its
owning source, focused and repository-wide validation are green as required,
documentation matches behavior, the diff contains no unrelated work or secret
material, and every explicitly requested push is verified on the target branch.
